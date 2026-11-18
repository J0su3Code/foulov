import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../src/rust/api/backup.dart';

/// Sauvegarde chiffrée (docs/SECURITY.md §7).
///
/// Le secret de la phrase de 24 mots est gardé dans le coffre du système (Keystore / Keychain), pour que la
/// sauvegarde automatique puisse tourner. Il ne quitte jamais le téléphone ; la sauvegarde, elle, est chiffrée
/// avant d'être déposée sur R2 (`b/<ton identifiant>/latest`, remplacée à chaque fois).
class BackupService extends ChangeNotifier {
  BackupService._();
  static final instance = BackupService._();

  static const _store = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const _secretKey = 'foulov.backup_secret';
  static const _lastKey = 'foulov.backup_last';
  static const every = Duration(hours: 24);

  bool enabled = false;
  DateTime? last;
  bool running = false;
  String? error;

  Future<void> load() async {
    enabled = (await _store.read(key: _secretKey)) != null;
    final l = await _store.read(key: _lastKey);
    last = l == null ? null : DateTime.tryParse(l);
    notifyListeners();
  }

  Future<Uint8List?> _secret() async {
    final s = await _store.read(key: _secretKey);
    return s == null ? null : base64Decode(s);
  }

  /// Phrase à afficher (pour la revoir). `null` si la sauvegarde n'est pas activée.
  Future<String?> phrase() async {
    final s = await _secret();
    return s == null ? null : backupSecretToPhrase(secret: s);
  }

  /// Après que l'utilisateur a noté sa phrase et l'a vérifiée : on garde le secret et on sauvegarde aussitôt.
  Future<void> enable(Uint8List secret, SupabaseClient db) async {
    await _store.write(key: _secretKey, value: base64Encode(secret));
    enabled = true;
    notifyListeners();
    await backupNow(db);
  }

  /// Sauvegarde si la dernière date de plus de 24 h (appelée à l'ouverture de l'app).
  Future<void> maybeBackup(SupabaseClient db) async {
    if (!enabled) await load();
    if (!enabled || running) return;
    if (last != null && DateTime.now().difference(last!) < every) return;
    await backupNow(db);
  }

  Future<bool> backupNow(SupabaseClient db) async {
    final secret = await _secret();
    if (secret == null || running) return false;
    running = true;
    error = null;
    notifyListeners();
    try {
      final data = await backupExport(secret: secret);
      final link = await db.functions
          .invoke('media', body: {'action': 'backup_upload', 'size': data.length})
          .timeout(const Duration(seconds: 30));
      if (link.status != 200 || link.data is! Map) throw StateError('lien ${link.status}');
      final res = await http
          .put(Uri.parse((link.data as Map)['url'] as String), body: data)
          .timeout(const Duration(minutes: 10));
      if (res.statusCode != 200) throw StateError('dépôt ${res.statusCode}');
      last = DateTime.now();
      await _store.write(key: _lastKey, value: last!.toIso8601String());
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] sauvegarde : $e');
      error = 'La dernière sauvegarde n\'a pas abouti. Elle sera retentée automatiquement.';
      return false;
    } finally {
      running = false;
      notifyListeners();
    }
  }

  /// Une sauvegarde existe-t-elle déjà sur le serveur pour ce compte ? (restauration sur un nouveau téléphone)
  Future<DateTime?> remoteBackupDate(SupabaseClient db) async {
    final r = await db.functions
        .invoke('media', body: {'action': 'backup_status'})
        .timeout(const Duration(seconds: 20));
    if (r.status != 200 || r.data is! Map || (r.data as Map)['exists'] != true) return null;
    return HttpDate.tryParse((r.data as Map)['at'] as String? ?? '') ?? DateTime.now();
  }

  /// Restaure avec la phrase tapée. Garde le secret pour les sauvegardes suivantes.
  Future<RestoreSummary> restore(String phrase, SupabaseClient db) async {
    final secret = await backupPhraseToSecret(phrase: phrase);
    final link = await db.functions
        .invoke('media', body: {'action': 'backup_download'})
        .timeout(const Duration(seconds: 30));
    if (link.status != 200 || link.data is! Map) throw StateError('lien ${link.status}');
    final res = await http.get(Uri.parse((link.data as Map)['url'] as String)).timeout(const Duration(minutes: 10));
    if (res.statusCode != 200) throw StateError('téléchargement ${res.statusCode}');
    final sum = await backupImport(secret: secret, data: res.bodyBytes);
    await _store.write(key: _secretKey, value: base64Encode(secret));
    enabled = true;
    notifyListeners();
    return sum;
  }

  /// Déconnexion : le secret de ce compte ne reste pas sur le téléphone.
  Future<void> forget() async {
    await _store.delete(key: _secretKey);
    await _store.delete(key: _lastKey);
    enabled = false;
    last = null;
    notifyListeners();
  }
}

/// Date HTTP (« Tue, 18 Nov 2026 08:12:00 GMT ») sans dépendance.
abstract final class HttpDate {
  static const _m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static DateTime? tryParse(String s) {
    final p = s.split(RegExp(r'[ ,:]+'));
    if (p.length < 7) return null;
    final mo = _m.indexOf(p[2]);
    if (mo < 0) return null;
    return DateTime.utc(
      int.parse(p[3]),
      mo + 1,
      int.parse(p[1]),
      int.parse(p[4]),
      int.parse(p[5]),
      int.parse(p[6]),
    ).toLocal();
  }
}
