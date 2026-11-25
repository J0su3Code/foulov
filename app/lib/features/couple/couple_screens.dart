import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../account/account_service.dart';
import '../account/danger_screen.dart';
import '../../ui/love.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../backup/backup_service.dart';
import '../chat/home_shell.dart';
import '../chat/chat_service.dart';
import 'couple_service.dart';
import 'incoming_links.dart';

String _pretty(String code) => code.length == 10 ? '${code.substring(0, 5)}-${code.substring(5)}' : code;

TextStyle? _title(BuildContext c) =>
    Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.08);
TextStyle? _soft(BuildContext c) =>
    Theme.of(c).textTheme.bodyLarge?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant, height: 1.4);

// ===================================================================== aiguillage

/// Oriente vers le bon écran selon l'état du couple.
class CoupleGate extends StatefulWidget {
  const CoupleGate({super.key, required this.auth, required this.couple});

  final AuthService auth;
  final CoupleService couple;

  /// Fermer la bulle ou supprimer le compte depuis n'importe quel écran (réglages, accueil sans espace).
  static Future<void> end(Future<void> Function() action) => _CoupleGateState._end(action);

  @override
  State<CoupleGate> createState() => _CoupleGateState();
}

class _CoupleGateState extends State<CoupleGate> with WidgetsBindingObserver {
  late Future<CoupleState> _state = _open();
  CoupleState? _last;

  /// Écran en cours (un seul à la fois) : pour fermer la bulle depuis les réglages.
  static _CoupleGateState? _current;

  /// Fermer la bulle ou supprimer le compte : la messagerie est d'abord arrêtée (plus d'écriture dans la base),
  /// puis `action` s'exécute (serveur et remise à zéro), et l'aiguillage repart de zéro. Lève l'erreur de `action`.
  static Future<void> _end(Future<void> Function() action) async {
    final g = _current;
    if (g == null) return action();
    g.setState(() => g._closing = true);
    await WidgetsBinding.instance.endOfFrame; // la messagerie est démontée (abonnements fermés)
    try {
      await action();
      g.widget.couple.reset();
    } finally {
      if (g.mounted) {
        g._closing = false;
        g._reload();
      }
    }
  }

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _current = this;
    WidgetsBinding.instance.addObserver(this);
    IncomingLinks.invitation.addListener(_onInvitation);
  }

  // Une invitation arrive (lien touché pendant que l'app est ouverte) : l'aiguillage la montre aussitôt.
  void _onInvitation() {
    if (mounted) setState(() {});
  }

  /// Ouverture instantanée : le dernier état connu s'affiche tout de suite (même hors ligne) ; le serveur est
  /// interrogé en arrière-plan, et l'écran ne change que si quelque chose a vraiment changé (nouvelle clé, etc.).
  Future<CoupleState> _open() async {
    final cached = await widget.couple.cached();
    if (cached == null) return widget.couple.load();
    unawaited(_refreshInBackground(cached));
    return cached;
  }

  Future<void> _refreshInBackground(CoupleState shown) async {
    try {
      final fresh = await widget.couple.load();
      final same =
          fresh.coupleId == shown.coupleId &&
          fresh.partnerId == shown.partnerId &&
          fresh.verified == shown.verified &&
          !fresh.keyChanged &&
          fresh.restoreFrom == null &&
          !fresh.ended &&
          fresh.complete;
      if (!same && mounted) {
        setState(() {
          _state = Future.value(fresh);
        });
      }
    } catch (e) {
      // Hors ligne : on reste sur l'état connu ; la messagerie réessaiera d'elle-même.
      if (kDebugMode) debugPrint('[FOULOVE] hors ligne au démarrage : $e');
    }
  }

  @override
  void dispose() {
    IncomingLinks.invitation.removeListener(_onInvitation);
    if (_current == this) _current = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Écran « la clé a changé » : au retour dans l'app, on relit la clé publiée (elle a pu changer encore).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (_last?.keyChanged ?? false)) _reload();
  }

  // Après avoir rejoint avec le code seul, l'écran de vérification s'affiche : il faut échanger les liens.
  bool _showSymbols = false;

  void _joined() {
    if (widget.couple.joinedWithInvitation) {
      // Invitation complète : clés vérifiées des deux côtés, rien à comparer. On fête ça.
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 700),
          pageBuilder: (_, a, _) => FadeTransition(opacity: a, child: const CelebrationScreen()),
        ),
      );
    } else {
      _showSymbols = true;
    }
    _reload();
  }

  // Le chargement est lancé hors de setState, et l'affectation est dans un bloc : avec une flèche, « _state = next »
  // renverrait le Future lui-même, ce que setState refuse (et l'écran ne se redessinerait pas).
  void _reload() {
    final next = widget.couple.load();
    setState(() {
      _state = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CoupleState>(
      future: _state,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Message(
            title: 'Petit souci de connexion',
            body: 'Impossible de joindre votre espace pour le moment. Vérifie ta connexion puis réessaie.',
            action: ('Réessayer', _reload),
          );
        }
        final s = snap.data;
        if (s == null || _closing) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        _last = s;
        if (s.ended) return _EndedScreen(couple: widget.couple, auth: widget.auth, onDone: _reload);
        final invite = IncomingLinks.invitation.value;
        if (invite != null) {
          if (!s.complete) {
            return InvitationReceivedScreen(
              key: ValueKey(invite),
              couple: widget.couple,
              invitation: invite,
              replacesOwnBubble: s.hasCouple,
              onJoined: _joined,
              onDismiss: () async {
                await IncomingLinks.clearInvitation();
                _reload();
              },
            );
          }
          // Déjà réunis (par exemple, chacun avait envoyé un lien à l'autre) : l'invitation ne sert plus.
          WidgetsBinding.instance.addPostFrameCallback((_) => IncomingLinks.clearInvitation());
        }
        if (!s.hasCouple) {
          return ChoiceScreen(couple: widget.couple, onDone: _reload, onJoined: _joined, auth: widget.auth);
        }
        if (!s.complete || s.partnerIdentity == null) {
          return InviteScreen(
            couple: widget.couple,
            auth: widget.auth,
            onPartner: _reload,
            onCancelled: (join) {
              _reload();
              if (join) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => JoinScreen(
                      couple: widget.couple,
                      onJoined: () {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        _joined();
                      },
                    ),
                  ),
                );
              }
            },
          );
        }
        // Nouvelle clé du partenaire : avant tout le reste, un nouvel échange de liens.
        if (s.keyChanged) {
          return KeyChangeScreen(
            couple: widget.couple,
            partnerId: s.partnerId!,
            newIdentity: s.partnerIdentity!,
            onDone: _reload,
          );
        }
        if (s.restoreFrom != null) {
          return RestoreScreen(couple: widget.couple, backupDate: s.restoreFrom!, onDone: _reload);
        }
        if ((!s.verified && !s.verifyLater) || _showSymbols) {
          return VerifyScreen(
            couple: widget.couple,
            partnerId: s.partnerId!,
            partnerIdentity: s.partnerIdentity!,
            alreadyVerified: s.verified,
            onVerified: () {
              _showSymbols = false;
              _reload();
            },
            onLater: s.verified
                ? null
                : () async {
                    await widget.couple.setVerifyLater(s.partnerIdentity!);
                    _showSymbols = false;
                    _reload();
                  },
          );
        }
        return _ChatHost(
          key: ValueKey(s.coupleId),
          state: s,
          auth: widget.auth,
          // Rechargé : une clé changée (bandeau de la conversation) mène à la nouvelle vérification.
          onShowSymbols: () {
            _showSymbols = true;
            _reload();
          },
        );
      },
    );
  }
}

/// L'autre a fermé votre bulle (ou supprimé son compte) : l'historique est encore ici, plus rien ne peut partir.
class _EndedScreen extends StatefulWidget {
  const _EndedScreen({required this.couple, required this.auth, required this.onDone});

  final CoupleService couple;
  final AuthService auth;
  final VoidCallback onDone;

  @override
  State<_EndedScreen> createState() => _EndedScreenState();
}

class _EndedScreenState extends State<_EndedScreen> {
  bool _busy = false;

  Future<void> _erase() async {
    setState(() => _busy = true);
    try {
      await AccountService.forgetEndedCouple(Supabase.instance.client);
      widget.couple.reset();
      widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('L\'effacement n\'a pas abouti. Réessaie.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LoveBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.heart_broken_outlined, size: 64, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(height: 16),
              Text('Votre bulle a été fermée', style: _title(context), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                'Ton amour a fermé votre bulle, ou supprimé son compte. Vos échanges sont encore sur ce téléphone, '
                'mais plus rien ne peut être envoyé ni reçu.\n\nPour créer une nouvelle bulle, efface d\'abord celle-ci : '
                'messages, photos, lettres et sauvegarde disparaîtront de ce téléphone et de nos serveurs.',
                style: _soft(context),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else ...[
                FilledButton(onPressed: _erase, child: const Text('Effacer et recommencer')),
                TextButton(onPressed: widget.auth.signOut, child: const Text('Me déconnecter')),
                TextButton(
                  onPressed: () => DangerScreen.open(context, deleteAccount: true),
                  child: Text('Supprimer mon compte', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Crée le service de messagerie pour la durée de l'écran (abonnement temps réel, boîte d'envoi).
class _ChatHost extends StatefulWidget {
  const _ChatHost({super.key, required this.state, required this.auth, required this.onShowSymbols});

  final CoupleState state;
  final AuthService auth;
  final VoidCallback onShowSymbols;

  @override
  State<_ChatHost> createState() => _ChatHostState();
}

class _ChatHostState extends State<_ChatHost> {
  late final ChatService _service = ChatService(
    Supabase.instance.client,
    partnerId: widget.state.partnerId!,
    coupleId: widget.state.coupleId!,
    coupleSince: widget.state.since,
    verified: widget.state.verified,
  );
  late final Future<void> _ready = _service.start();

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snap) => snap.connectionState != ConnectionState.done
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : HomeShell(
            service: _service,
            since: widget.state.since,
            onShowSymbols: widget.onShowSymbols,
            onSignOut: widget.auth.signOut,
          ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body, required this.action});

  final String title;
  final String body;
  final (String, VoidCallback) action;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LoveBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(title, style: _title(context)),
              const SizedBox(height: 10),
              Text(body, style: _soft(context)),
              const Spacer(),
              FilledButton(onPressed: action.$2, child: Text(action.$1)),
            ],
          ),
        ),
      ),
    ),
  );
}

// ===================================================================== choix

class ChoiceScreen extends StatefulWidget {
  const ChoiceScreen({
    super.key,
    required this.couple,
    required this.onDone,
    required this.onJoined,
    required this.auth,
  });

  final CoupleService couple;
  final VoidCallback onDone;
  final VoidCallback onJoined;
  final AuthService auth;

  @override
  State<ChoiceScreen> createState() => _ChoiceScreenState();
}

class _ChoiceScreenState extends State<ChoiceScreen> {
  bool _busy = false;

  /// « Mon amour m'a invité(e) » : si l'invitation est déjà copiée, on la prend ; sinon, scanner ou coller.
  Future<void> _join() async {
    final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (CoupleService.isFullInvitation(t)) {
      IncomingLinks.invitation.value = t;
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JoinScreen(
          couple: widget.couple,
          onJoined: () {
            Navigator.of(context).pop();
            widget.onJoined();
          },
        ),
      ),
    );
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await widget.couple.createCouple();
      HapticFeedback.mediumImpact();
      widget.onDone();
    } catch (e, st) {
      // Journal technique en mode développement uniquement (aucune donnée personnelle).
      if (kDebugMode) debugPrint('[FOULOVE] création de l\'espace : $e\n$st');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La création de votre espace n\'a pas abouti. Réessaie dans un instant.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LoveBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded),
                    tooltip: 'Compte',
                    onSelected: (v) =>
                        v == 'out' ? widget.auth.signOut() : DangerScreen.open(context, deleteAccount: true),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'out', child: Text('Se déconnecter')),
                      PopupMenuItem(value: 'delete', child: Text('Supprimer mon compte')),
                    ],
                  ),
                ),
                const Spacer(),
                const Center(child: EntwinedHeart(size: 170)),
                const SizedBox(height: 14),
                Text('Deux cœurs,\nune seule bulle.', style: _title(context), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('Un seul de vous deux invite l\'autre.', style: _soft(context), textAlign: TextAlign.center),
                const Spacer(),
                if (_busy)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  _ChoiceCard(
                    icon: Icons.send_rounded,
                    title: 'J\'invite mon amour',
                    subtitle: 'Je commence, et je lui envoie un lien',
                    onTap: _create,
                  ),
                  const SizedBox(height: 12),
                  _ChoiceCard(
                    icon: Icons.mark_email_read_rounded,
                    title: 'Mon amour m\'a invité(e)',
                    subtitle: 'J\'ai reçu un lien ou un QR code',
                    onTap: _join,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une des deux portes d'entrée, de même poids : aucune n'est « le premier bouton » qu'on touche sans lire.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: .14), shape: BoxShape.circle),
                child: Icon(icon, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================================================================== invitation reçue par un lien

/// FouLove s'est ouverte avec une invitation (lien touché, QR code, ou invitation copiée). Un seul bouton.
/// Si ce compte avait déjà créé une bulle vide (les deux ont touché « J'invite »), elle est remplacée.
class InvitationReceivedScreen extends StatefulWidget {
  const InvitationReceivedScreen({
    super.key,
    required this.couple,
    required this.invitation,
    required this.replacesOwnBubble,
    required this.onJoined,
    required this.onDismiss,
  });

  final CoupleService couple;
  final String invitation;
  final bool replacesOwnBubble;
  final VoidCallback onJoined, onDismiss;

  @override
  State<InvitationReceivedScreen> createState() => _InvitationReceivedScreenState();
}

class _InvitationReceivedScreenState extends State<InvitationReceivedScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.replacesOwnBubble) await widget.couple.cancelPendingCouple();
      final r = await widget.couple.join(widget.invitation);
      switch (r) {
        case JoinResult.joined:
          await IncomingLinks.clearInvitation();
          HapticFeedback.heavyImpact();
          widget.onJoined();
          return;
        case JoinResult.invalidCode:
          _error = 'Cette invitation a expiré ou a déjà servi. Demande à ton amour de t\'en renvoyer une.';
        case JoinResult.keyMismatch:
          _error =
              'Les clés reçues ne correspondent pas à l\'invitation. Par sécurité, rien n\'est fait. '
              'Demandez une nouvelle invitation.';
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] invitation reçue : $e');
      final m = e.toString();
      _error = m.contains('trop de tentatives')
          ? 'Trop de tentatives. Patiente une heure avant de réessayer.'
          : m.contains('déjà dans un couple')
          ? 'Tu es déjà dans une bulle.'
          : 'Impossible de rejoindre pour le moment. Vérifie ta connexion puis réessaie.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: LoveBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Center(child: EntwinedHeart(size: 190)),
                const SizedBox(height: 18),
                Text('Ton amour t\'invite\ndans sa bulle 💞', style: _title(context), textAlign: TextAlign.center),
                if (widget.replacesOwnBubble) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Tu avais aussi créé une bulle. Elle est vide : elle sera remplacée par celle de ton amour.',
                    style: _soft(context),
                    textAlign: TextAlign.center,
                  ),
                ],
                const Spacer(),
                if (_error != null) ...[Text(_error!, style: TextStyle(color: cs.error)), const SizedBox(height: 12)],
                if (_busy)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.favorite_rounded),
                    label: const Text('Rejoindre sa bulle'),
                    onPressed: _join,
                  ),
                  TextButton(onPressed: widget.onDismiss, child: const Text('Pas maintenant')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================================== invitation (côté créateur)

class InviteScreen extends StatefulWidget {
  const InviteScreen({
    super.key,
    required this.couple,
    required this.auth,
    required this.onPartner,
    required this.onCancelled,
  });

  final CoupleService couple;
  final AuthService auth;
  final VoidCallback onPartner;

  /// Bulle en attente annulée ; `join` : on veut plutôt rejoindre celle de l'autre.
  final void Function(bool join) onCancelled;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  String? _code;
  String? _qr;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _newCode();
    // Toutes les 3 secondes : Malik a-t-il rejoint ?
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  bool _checking = false;

  /// Une seule vérification à la fois : une requête lente ne doit pas en lancer une seconde en parallèle.
  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final s = await widget.couple.load();
      if (s.complete && s.partnerIdentity != null) {
        _poll?.cancel();
        await widget.couple.receiveHello(s.partnerId!);
        // Invitation complète : la preuve reçue vérifie sa clé, rien à comparer.
        final verified = await widget.couple.verifyJoinProof(s.partnerId!);
        HapticFeedback.heavyImpact();
        if (!mounted) return;
        if (verified) {
          await Navigator.of(context).push(
            PageRouteBuilder<void>(
              transitionDuration: const Duration(milliseconds: 700),
              pageBuilder: (_, a, _) => FadeTransition(opacity: a, child: const CelebrationScreen()),
            ),
          );
        }
        if (mounted) widget.onPartner();
      }
    } catch (e) {
      // Réseau momentané : on réessaie au passage suivant.
      if (kDebugMode) debugPrint('[FOULOVE] attente du partenaire : $e');
    } finally {
      _checking = false;
    }
  }

  Future<void> _menu(String v) async {
    if (v == 'out') {
      await widget.auth.signOut();
      return;
    }
    if (v == 'delete') {
      // La fonction `account` ferme aussi la bulle en attente : personne ne l'a encore rejointe.
      DangerScreen.open(context, deleteAccount: true);
      return;
    }
    _poll?.cancel();
    try {
      // Personne ne l'a encore rejointe : l'annuler ne fait rien perdre.
      await widget.couple.cancelPendingCouple();
      widget.onCancelled(v == 'join');
    } catch (_) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ça n\'a pas marché. Vérifie ta connexion.')));
      }
    }
  }

  Future<void> _newCode({bool forceNew = false}) async {
    try {
      final code = await widget.couple.currentInvitation(forceNew: forceNew);
      final qr = await widget.couple.qrPayload(code);
      if (mounted) {
        setState(() {
          _code = code;
          _qr = qr;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: LoveBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            children: [
              Row(
                children: [
                  Expanded(child: Text('Invite ton amour', style: _title(context))),
                  // Une sortie, toujours : on a pu toucher « Créer » au lieu de « J'ai reçu une invitation ».
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded),
                    tooltip: 'Plus',
                    onSelected: _menu,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'join', child: Text('J\'ai plutôt reçu une invitation')),
                      PopupMenuItem(value: 'cancel', child: Text('Annuler cette bulle')),
                      PopupMenuItem(value: 'out', child: Text('Se déconnecter')),
                      PopupMenuItem(value: 'delete', child: Text('Supprimer mon compte')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const _Steps(
                steps: [
                  (Icons.send_rounded, 'Envoie le lien'),
                  (Icons.touch_app_rounded, 'Ton amour le touche'),
                  (Icons.favorite_rounded, 'Votre bulle est née'),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                icon: const Icon(Icons.send_rounded),
                label: const Text('Envoyer le lien à mon amour'),
                onPressed: _code == null
                    ? null
                    : () async =>
                          SharePlus.instance.share(ShareParams(text: await widget.couple.invitationText(_code!))),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(child: Divider(color: cs.outline)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('À côté de toi ? Fais-lui scanner', style: _soft(context)?.copyWith(fontSize: 13)),
                  ),
                  Expanded(child: Divider(color: cs.outline)),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: cs.secondary.withValues(alpha: .28), blurRadius: 40, spreadRadius: 2)],
                  ),
                  child: _qr == null
                      ? const SizedBox.square(dimension: 200, child: Center(child: CircularProgressIndicator()))
                      : QrImageView(
                          data: _qr!,
                          size: 200,
                          backgroundColor: cs.surfaceContainer,
                          eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.circle, color: cs.primary),
                          dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.circle,
                            color: cs.onSurface,
                          ),
                          semanticsLabel: 'QR code d\'invitation',
                        ),
                ),
              ),
              const SizedBox(height: 18),
              const Center(child: BeatingHeart(size: 42)),
              Center(child: Text('En attente de ton amour…', style: _soft(context))),
              const SizedBox(height: 10),
              if (_code != null)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Le lien ne s\'ouvre pas chez ton amour ?', style: _soft(context)?.copyWith(fontSize: 14)),
                    children: [
                      Text(
                        'Copie l\'invitation et envoie-la. Ton amour la copie, ouvre FouLove, touche '
                        '« Mon amour m\'a invité(e) » : elle est reconnue toute seule. Ou il tape ce code :',
                        style: _soft(context)?.copyWith(fontSize: 13.5),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        _pretty(_code!),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        'Valable 24 h, une fois. Avec le code seul, vous échangerez vos liens juste après.',
                        textAlign: TextAlign.center,
                        style: _soft(context)?.copyWith(fontSize: 12.5),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Copier l\'invitation'),
                            onPressed: () async {
                              final text = await widget.couple.invitationText(_code!);
                              await Clipboard.setData(ClipboardData(text: text));
                              if (context.mounted) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(const SnackBar(content: Text('Invitation copiée')));
                              }
                            },
                          ),
                          TextButton(
                            onPressed: () => _newCode(forceNew: true),
                            child: const Text('Nouveau code'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              // Erreur fréquente : les deux ont touché « J'invite ». Une sortie visible, pas cachée dans un menu.
              OutlinedButton.icon(
                icon: const Icon(Icons.mark_email_read_rounded, size: 18),
                label: const Text('C\'est mon amour qui m\'a invité(e)'),
                onPressed: () => _menu('join'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================================================================== rejoindre

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.couple, required this.onJoined});

  final CoupleService couple;
  final VoidCallback onJoined;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();
  // Créé une seule fois : le recréer à chaque reconstruction relancerait la caméra.
  final _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _scan = true;
  bool _busy = false;
  // Le scanner signale le même QR code plusieurs fois par seconde : on ne le traite qu'une fois.
  // Après un échec, il faut appuyer sur « Scanner à nouveau » (chaque essai compte dans la limite de 10 par heure).
  String? _scanned;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _camera.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    final v = cap.barcodes.firstOrNull?.rawValue;
    if (v == null || !CoupleService.isFullInvitation(v) || _scanned != null) return;
    _scanned = v;
    _camera.stop();
    _submit(v);
  }

  Future<void> _paste() async {
    final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!CoupleService.isFullInvitation(t)) {
      setState(() => _error = 'Aucune invitation dans le presse-papiers. Copie d\'abord tout le message reçu.');
      return;
    }
    await _submit(t);
  }

  void _rescan() {
    setState(() {
      _scanned = null;
      _error = null;
    });
    _camera.start();
  }

  Future<void> _submit(String input) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.couple.join(input);
      switch (r) {
        case JoinResult.joined:
          HapticFeedback.heavyImpact();
          widget.onJoined();
          return;
        case JoinResult.invalidCode:
          _error = 'Ce code ne fonctionne pas. Il a peut-être expiré ou déjà servi : demande un nouveau code.';
        case JoinResult.keyMismatch:
          _error =
              'Les clés reçues ne correspondent pas au QR code. Par sécurité, l\'appairage est arrêté. '
              'Recommencez ensemble avec un nouveau code.';
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] rejoindre : $e');
      final m = e.toString();
      if (m.contains('déjà dans un couple')) {
        // Ce compte a déjà un espace : l'aiguillage affiche le bon écran.
        widget.onJoined();
        return;
      }
      _error = m.contains('trop de tentatives')
          ? 'Trop de tentatives. Patiente une heure avant de réessayer.'
          : 'Impossible de rejoindre pour le moment. Vérifie ta connexion puis réessaie.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final normalized = _code.text.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Rejoindre')),
      body: LoveBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, icon: Icon(Icons.qr_code_scanner), label: Text('Scanner')),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.content_paste_rounded),
                      label: Text('Coller ou saisir'),
                    ),
                  ],
                  selected: {_scan},
                  onSelectionChanged: (v) => setState(() => _scan = v.first),
                ),
                const SizedBox(height: 20),
                if (_scan)
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(controller: _camera, onDetect: _onDetect),
                          IgnorePointer(
                            child: Center(
                              child: Container(
                                width: 230,
                                height: 230,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(32),
                                  border: Border.all(color: cs.secondary, width: 3),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Coller l\'invitation'),
                    onPressed: _busy ? null : _paste,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Copie le message que ton amour t\'a envoyé, puis touche ce bouton. Ou tape juste le code :',
                    style: _soft(context),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 11,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(letterSpacing: 4, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      hintText: 'K7Q4M-9XHPT',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => normalized.length == 10 ? _submit(normalized) : null,
                  ),
                  const Spacer(),
                ],
                if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: TextStyle(color: cs.error))],
                const SizedBox(height: 14),
                if (_busy)
                  const Center(
                    child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
                  )
                else if (_scan && _scanned != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scanner à nouveau'),
                    onPressed: _rescan,
                  )
                else if (!_scan)
                  FilledButton(
                    onPressed: normalized.length == 10 ? () => _submit(normalized) : null,
                    child: const Text('Rejoindre'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================================== vérification par les liens

/// Le couple s'est formé avec le code seul (ou un ancien QR code) : les clés ne sont pas encore vérifiées.
/// Chacun envoie son lien par une autre messagerie et colle celui de l'autre. Les 7 symboles d'avant ont été
/// retirés : 42 bits ne suffisaient pas contre un serveur malveillant (docs/SECURITY.md §5).
class VerifyScreen extends StatelessWidget {
  const VerifyScreen({
    super.key,
    required this.couple,
    required this.partnerId,
    required this.partnerIdentity,
    required this.onVerified,
    this.alreadyVerified = false,
    this.onLater,
  });

  final CoupleService couple;
  final String partnerId;
  final Uint8List partnerIdentity;
  final VoidCallback onVerified;

  /// « Plus tard » : entrer dans la conversation sans avoir vérifié (absent si c'est déjà vérifié).
  final VoidCallback? onLater;

  /// Vrai si ce téléphone a déjà vérifié la clé du partenaire (QR code) : il ne reste qu'à envoyer son lien.
  final bool alreadyVerified;

  Future<void> _done(BuildContext context) async {
    HapticFeedback.heavyImpact();
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, a, _) => FadeTransition(opacity: a, child: const CelebrationScreen()),
      ),
    );
    onVerified();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: LoveBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Scellez votre lien', style: _title(context)),
                const SizedBox(height: 8),
                Text(
                  alreadyVerified
                      ? 'Ce téléphone a déjà reconnu celui de ton amour. Envoie-lui ton lien (WhatsApp, SMS…) : '
                            'en le collant dans FouLove, son téléphone reconnaîtra le tien.'
                      : 'Dernière étape, 10 secondes : envoie ton lien à ton amour par une autre messagerie '
                            '(WhatsApp, SMS…), puis copie le sien et colle-le ici.',
                  style: _soft(context),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Ces liens prouvent que personne ne s\'est glissé entre vous, pas même nos serveurs.',
                        style: _soft(context)?.copyWith(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (alreadyVerified) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Envoyer mon lien'),
                    onPressed: () async => SharePlus.instance.share(ShareParams(text: await couple.fingerprintLink())),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.favorite),
                    label: const Text('Continuer'),
                    onPressed: () => _done(context),
                  ),
                ] else ...[
                  LinkExchange(
                    couple: couple,
                    partnerId: partnerId,
                    identity: partnerIdentity,
                    onVerified: () => _done(context),
                  ),
                  if (onLater != null)
                    TextButton(
                      onPressed: onLater,
                      child: const Text('Plus tard'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// À distance, sans appel : chacun envoie son « lien de retrouvailles » (l'empreinte de sa clé) par une autre
/// messagerie, et **touche** celui de l'autre (FouLove s'ouvre et le vérifie tout seul) ou le colle.
/// S'il correspond à la clé reçue, elle est vérifiée.
class LinkExchange extends StatefulWidget {
  const LinkExchange({
    super.key,
    required this.couple,
    required this.partnerId,
    required this.identity,
    required this.onVerified,
    this.keyChange = false,
  });

  final CoupleService couple;
  final String partnerId;
  final Uint8List identity;
  final bool keyChange;
  final Future<void> Function() onVerified;

  @override
  State<LinkExchange> createState() => _LinkExchangeState();
}

class _LinkExchangeState extends State<LinkExchange> {
  @override
  void initState() {
    super.initState();
    IncomingLinks.idLink.addListener(_incoming);
    WidgetsBinding.instance.addPostFrameCallback((_) => _incoming());
  }

  @override
  void dispose() {
    IncomingLinks.idLink.removeListener(_incoming);
    super.dispose();
  }

  // Lien touché dans WhatsApp : FouLove s'est ouverte avec lui.
  void _incoming() {
    final t = IncomingLinks.idLink.value;
    if (t == null || !mounted) return;
    IncomingLinks.idLink.value = null;
    _try(t);
  }

  Future<void> _try(String t) async {
    final ok = await widget.couple.acceptByLink(widget.partnerId, widget.identity, t, keyChange: widget.keyChange);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.heavyImpact();
      await widget.onVerified();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            CoupleService.isIdLink(t)
                ? 'Ce lien ne correspond pas à la clé reçue. N\'allez pas plus loin : parlez-en de vive voix.'
                : 'Copie d\'abord tout le message de ton amour, puis touche « Coller son lien ».',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Steps(
          steps: const [
            (Icons.send_rounded, 'Envoie ton lien'),
            (Icons.touch_app_rounded, 'Touche le sien'),
            (Icons.verified_rounded, 'C\'est vérifié'),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Envoyer mon lien'),
          onPressed: () async => SharePlus.instance.share(ShareParams(text: await widget.couple.fingerprintLink())),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.content_paste_rounded, size: 18),
          label: const Text('Coller son lien'),
          onPressed: () async => _try((await Clipboard.getData(Clipboard.kTextPlain))?.text ?? ''),
        ),
        const SizedBox(height: 6),
        Text(
          'Le lien de ton amour s\'ouvre tout seul dans FouLove quand tu le touches.',
          textAlign: TextAlign.center,
          style: _soft(context)?.copyWith(fontSize: 12.5, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Montrer plutôt qu'écrire : une petite frise d'étapes avec icônes (les gens ne lisent pas les paragraphes).
class _Steps extends StatelessWidget {
  const _Steps({required this.steps});

  final List<(IconData, String)> steps;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      if (i > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Icon(Icons.arrow_forward_rounded, size: 18, color: cs.outline),
          ),
        );
      }
      children.add(
        Expanded(
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: .13), shape: BoxShape.circle),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(steps[i].$1, color: cs.primary, size: 24),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor: cs.primary,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                steps[i].$2,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.onSurface, height: 1.2),
              ),
            ],
          ),
        ),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

// ===================================================================== célébration

class CelebrationScreen extends StatelessWidget {
  const CelebrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LoveBackground(
        count: 24,
        child: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    const Center(child: EntwinedHeart(size: 240)),
                    const SizedBox(height: 18),
                    Text('Votre bulle est née.', style: _title(context), textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    Text(
                      'Désormais, tout ce que vous vous envoyez est chiffré sur vos deux téléphones. Rien que vous deux.',
                      style: _soft(context),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Entrer dans notre bulle'),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned.fill(child: HeartBurst()),
          ],
        ),
      ),
    );
  }
}

// ===================================================================== nouveau téléphone du partenaire

/// La clé publiée par le partenaire a changé. Ses nouveaux messages restent en attente, illisibles, jusqu'à ce que
/// vous échangiez vos liens : seul le lien de son nouveau téléphone, reçu par une autre messagerie, débloque la clé.
class KeyChangeScreen extends StatelessWidget {
  const KeyChangeScreen({
    super.key,
    required this.couple,
    required this.partnerId,
    required this.newIdentity,
    required this.onDone,
  });

  final CoupleService couple;
  final String partnerId;
  final Uint8List newIdentity;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.phonelink_lock_rounded, size: 44, color: cs.secondary),
              const SizedBox(height: 12),
              Text('La clé de ton amour a changé', style: _title(context)),
              const SizedBox(height: 8),
              Text(
                'C\'est normal après un nouveau téléphone ou une réinstallation. Pour être sûrs que personne ne s\'est '
                'glissé entre vous, envoyez-vous vos liens par une autre messagerie (WhatsApp, SMS…), puis collez celui '
                'de l\'autre. Ses nouveaux messages attendent, chiffrés, jusque-là.',
                style: _soft(context),
              ),
              const SizedBox(height: 14),
              Text(
                'Tu n\'as pas changé de téléphone avec lui ou elle ? N\'accepte rien et parlez-en de vive voix.',
                style: _soft(context)?.copyWith(fontSize: 13),
              ),
              const Spacer(),
              LinkExchange(
                couple: couple,
                partnerId: partnerId,
                identity: newIdentity,
                keyChange: true,
                onVerified: () async => onDone(),
              ),
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Accepter sans vérifier ?'),
                      content: const Text(
                        'Fais-le seulement si ton amour vient vraiment de changer de téléphone ou de réinstaller '
                        'FouLove. Vos messages restent chiffrés, mais tant que vous n\'aurez pas échangé vos liens, '
                        'vous ne serez pas sûrs que personne ne s\'est glissé entre vous.',
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Accepter')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await couple.acceptPartnerKeyUnverified(partnerId, newIdentity);
                  onDone();
                },
                child: const Text('Accepter sans vérifier'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================================================================== restauration

/// Nouveau téléphone : retrouver ses échanges avec sa phrase de 24 mots.
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key, required this.couple, required this.backupDate, required this.onDone});

  final CoupleService couple;
  final DateTime backupDate;
  final VoidCallback onDone;

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _phrase = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // La phrase s'affiche pendant qu'on la tape : ni capture d'écran, ni aperçu dans les apps récentes.
    _secure(true);
  }

  @override
  void dispose() {
    _secure(false);
    _phrase.dispose();
    super.dispose();
  }

  static Future<void> _secure(bool on) async {
    try {
      await const MethodChannel('foulove/notifications').invokeMethod<void>('secure', on);
    } catch (_) {}
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sum = await BackupService.instance.restore(_phrase.text, Supabase.instance.client);
      await widget.couple.restoreDone();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${sum.messages} messages et ${sum.media} photos, vidéos ou vocaux retrouvés.')),
      );
      widget.onDone();
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] restauration : $e');
      final m = e.toString();
      setState(() {
        _busy = false;
        _error = m.contains('phrase de récupération invalide')
            ? 'Cette phrase n\'est pas valable : vérifie chaque mot et leur ordre.'
            : m.contains('illisible')
            ? 'Cette phrase ne correspond pas à ta sauvegarde.'
            : 'La restauration n\'a pas abouti. Vérifie ta connexion puis réessaie.';
      });
    }
  }

  Future<void> _skip() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continuer sans restaurer ?'),
        content: const Text(
          'Tes anciens échanges ne seront pas sur ce téléphone. Tu ne pourras plus les restaurer ensuite.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retour')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuer')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.couple.restoreDone();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = widget.backupDate;
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à '
        '${d.hour.toString().padLeft(2, '0')} h ${d.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          children: [
            Icon(Icons.cloud_download_outlined, size: 44, color: cs.secondary),
            const SizedBox(height: 12),
            Text('Retrouver vos échanges', style: _title(context)),
            const SizedBox(height: 8),
            Text(
              'Une sauvegarde chiffrée existe (du $when). Tape ta phrase de 24 mots pour la retrouver sur ce téléphone. '
              'Les accents sont facultatifs.',
              style: _soft(context),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _phrase,
              minLines: 4,
              maxLines: 6,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: 'mot1 mot2 mot3 … mot24'),
            ),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: TextStyle(color: cs.error))],
            const SizedBox(height: 18),
            FilledButton(onPressed: _busy ? null : _restore, child: Text(_busy ? 'Restauration…' : 'Restaurer')),
            TextButton(onPressed: _busy ? null : _skip, child: const Text('Continuer sans restaurer')),
          ],
        ),
      ),
    );
  }
}
