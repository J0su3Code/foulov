import 'dart:async';
import 'dart:math';


import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bytea.dart';
import '../../src/rust/api/chat.dart';
import '../../src/rust/api/device.dart';
import 'push_service.dart';

/// Messagerie du couple : transporte les enveloppes chiffrées entre le cœur Rust et Supabase.
///
/// - Le chiffrement, l'historique et les doublons sont gérés par le cœur (`core/src/chat.rs`).
/// - Envoi : le message apparaît aussitôt (« en attente »), puis la boîte d'envoi est vidée vers le serveur,
///   avec de nouvelles tentatives espacées en cas de coupure. Un renvoi réutilise le même identifiant.
/// - Réception : Supabase Realtime signale chaque nouvelle enveloppe ; on récupère alors toutes celles en
///   attente (aucune ne se perd si l'app était fermée), on les traite dans l'ordre, puis on les supprime du serveur.
class ChatService extends ChangeNotifier with WidgetsBindingObserver {
  ChatService(this._db, {required this.partnerId, required this.coupleId});

  final SupabaseClient _db;
  final String partnerId;
  final String coupleId;

  static const _page = 60;

  /// Du plus récent au plus ancien (liste affichée à l'envers).
  final List<ChatMessage> messages = [];
  final Map<String, ChatMessage> _byId = {};
  bool hasMore = true;
  bool _loadingMore = false;

  /// La conversation est à l'écran et l'app au premier plan : les messages reçus sont aussitôt « lus ».
  bool _visible = false;
  bool _foreground = true;

  /// La clé du partenaire a changé : on n'affiche plus rien de nouveau tant qu'elle n'est pas revérifiée.
  bool partnerKeyChanged = false;

  RealtimeChannel? _channel;
  bool _pulling = false, _pullAgain = false;
  bool _flushing = false, _flushAgain = false;
  Timer? _retry;
  int _failures = 0;
  bool _disposed = false;

  String get _me => _db.auth.currentUser!.id;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await _loadPage();
    _channel = _db
        .channel('enveloppes-$_me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'envelopes',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'recipient_id', value: _me),
          callback: (_) => pull(),
        )
        .subscribe((status, error) {
      // À chaque (re)connexion, on rattrape ce qui est arrivé pendant la coupure.
      if (status == RealtimeSubscribeStatus.subscribed) pull();
    });
    unawaited(pull());
    unawaited(flush());
    unawaited(chatPurge().catchError((_) {}));
    unawaited(PushService.register(_db));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    final c = _channel;
    if (c != null) unawaited(_db.removeChannel(c));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(pull());
      unawaited(flush());
      unawaited(_readVisible());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  ChatMessage? byId(String id) => _byId[id];

  // ------------------------------------------------------------------ historique

  Future<void> _loadPage() async {
    final last = messages.isEmpty ? null : messages.last;
    final page = await chatMessages(beforeSentAt: last?.sentAt, beforeId: last?.id, limit: _page);
    for (final m in page) {
      if (_byId.containsKey(m.id)) continue;
      _byId[m.id] = m;
      messages.add(m);
    }
    hasMore = page.length == _page;
    _notify();
  }

  Future<void> loadMore() async {
    if (_loadingMore || !hasMore) return;
    _loadingMore = true;
    try {
      await _loadPage();
    } finally {
      _loadingMore = false;
    }
  }

  /// Les citations peuvent viser un message pas encore chargé : on le lit dans la base locale.
  Future<ChatMessage?> lookup(String id) async => _byId[id] ?? await chatMessage(id: id);

  void _upsert(ChatMessage m) {
    final old = _byId[m.id];
    _byId[m.id] = m;
    if (old != null) {
      final i = messages.indexWhere((x) => x.id == m.id);
      if (i >= 0) messages[i] = m;
      return;
    }
    // Insertion à sa place (ordre d'envoi), le plus souvent tout en haut.
    var i = 0;
    while (i < messages.length && _after(messages[i], m)) {
      i++;
    }
    messages.insert(i, m);
  }

  static bool _after(ChatMessage a, ChatMessage b) =>
      a.sentAt > b.sentAt || (a.sentAt == b.sentAt && a.id.compareTo(b.id) > 0);

  Future<void> _refresh(Iterable<String> ids) async {
    for (final id in ids) {
      final m = await chatMessage(id: id);
      if (m != null) _upsert(m);
    }
  }

  // ------------------------------------------------------------------ envoi

  Future<void> send(String text, {String? replyTo}) async {
    final s = await chatSendText(partner: partnerId, body: text, replyTo: replyTo);
    _upsert(s.message);
    _notify();
    unawaited(flush());
  }

  Future<void> react(String id, String emoji) async {
    final current = _byId[id]?.myReaction;
    // Toucher deux fois la même réaction la retire.
    await chatSendReaction(partner: partnerId, target: id, emoji: current == emoji ? '' : emoji);
    await _refresh([id]);
    _notify();
    unawaited(flush());
  }

  /// Vide la boîte d'envoi, dans l'ordre. Une seule exécution à la fois.
  Future<void> flush() async {
    if (_flushing) {
      _flushAgain = true;
      return;
    }
    _flushing = true;
    try {
      do {
        _flushAgain = false;
        for (final o in await chatOutbox()) {
          await _upload(o);
          final mid = await chatOutboxSent(envelopeId: o.envelopeId);
          if (mid != null) await _refresh([mid]);
          _notify();
        }
      } while (_flushAgain);
      _failures = 0;
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] envoi : $e');
      _scheduleRetry();
    } finally {
      _flushing = false;
    }
  }

  Future<void> _upload(Outgoing o) async {
    try {
      await _db.from('envelopes').insert({
        'id': o.envelopeId,
        'couple_id': coupleId,
        'sender_id': _me,
        'recipient_id': partnerId,
        'kind': o.kind,
        'ciphertext': toBytea(o.body),
        // Accusés de réception : pas de notification chez le partenaire.
        'urgent': o.urgent,
      });
    } on PostgrestException catch (e) {
      // Déjà déposée lors d'une tentative précédente (la réponse s'était perdue) : c'est un succès.
      if (e.code != '23505') rethrow;
    }
  }

  /// Nouvelles tentatives : 2 s, 4 s, 8 s… jusqu'à 1 min, avec un peu d'aléa.
  void _scheduleRetry() {
    _retry?.cancel();
    _failures = min(_failures + 1, 6);
    final ms = (1000 * pow(2, _failures)).toInt().clamp(2000, 60000) + Random().nextInt(700);
    _retry = Timer(Duration(milliseconds: ms), () {
      unawaited(flush());
      unawaited(pull());
    });
  }

  // ------------------------------------------------------------------ réception

  Future<void> pull() async {
    if (_pulling) {
      _pullAgain = true;
      return;
    }
    _pulling = true;
    try {
      do {
        _pullAgain = false;
        final rows = await _db
            .from('envelopes')
            .select('id, kind, ciphertext')
            .eq('sender_id', partnerId)
            .order('created_at')
            .limit(200);
        if (rows.isEmpty) break;
        final done = <String>[];
        final fresh = <String>[];
        for (final r in rows) {
          final id = r['id'] as String;
          try {
            final res = await chatReceive(
              partner: partnerId,
              envelopeId: id,
              envelope: Envelope(kind: r['kind'] as int, body: fromBytea(r['ciphertext'])),
            );
            done.add(id);
            final m = res.message;
            if (m != null) {
              _upsert(m);
              fresh.add(m.id);
            }
            if (res.updated.isNotEmpty) await _refresh(res.updated);
          } catch (e) {
            if (e.toString().contains('clé de ton partenaire a changé')) {
              partnerKeyChanged = true;
              _notify();
              return; // les enveloppes restent sur le serveur jusqu'à la nouvelle vérification
            }
            rethrow;
          }
        }
        _notify();
        if (done.isNotEmpty) await _db.from('envelopes').delete().inFilter('id', done);
        if (fresh.isNotEmpty) {
          final kind = _visible && _foreground ? 3 : 2; // « lu » implique « distribué »
          final rec = await chatSendReceipt(partner: partnerId, ids: fresh, kind: kind);
          if (rec != null && kind == 3) await _refresh(fresh);
          _notify();
          unawaited(flush());
        }
        if (rows.length == 200) _pullAgain = true;
      } while (_pullAgain);
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] réception : $e');
      _scheduleRetry();
    } finally {
      _pulling = false;
    }
  }

  // ------------------------------------------------------------------ lecture

  set visible(bool v) {
    _visible = v;
    if (v) unawaited(_readVisible());
  }

  bool get _onScreen => _visible && _foreground;

  Future<void> _readVisible() async {
    if (!_onScreen) return;
    unawaited(PushService.clear());
    try {
      final ids = await chatUnread();
      if (ids.isEmpty) return;
      await chatSendReceipt(partner: partnerId, ids: ids, kind: 3);
      await _refresh(ids);
      _notify();
      unawaited(flush());
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] accusé de lecture : $e');
    }
  }
}
