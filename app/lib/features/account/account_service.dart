import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../src/rust/api/device.dart';
import '../backup/backup_service.dart';
import '../dates/reminders.dart';
import '../lock/app_lock.dart';

/// Fermer sa bulle, supprimer son compte, remettre ce téléphone à zéro (docs/SECURITY.md §8).
abstract final class AccountService {
  static const _store = FlutterSecureStorage();

  /// Ce qui appartient à l'espace du couple sur ce téléphone (le reste — thème, code FouLove, session — est gardé
  /// quand on ferme seulement sa bulle).
  static const _coupleKeys = [
    'foulov.device.db_key',
    'foulov.couple_cache',
    'foulov.invitation',
    'foulov.restore_offered',
    'foulov.backup_secret',
    'foulov.backup_last',
    'foulov.local_owner',
    'foulov.verify_later',
  ];

  /// « close » : fichiers du couple et sauvegarde retirés de R2, espace supprimé (chez les deux).
  /// « delete » : la même chose, puis le compte lui-même.
  static Future<void> _server(SupabaseClient db, String action) async {
    final r = await db.functions.invoke('account', body: {'action': action}).timeout(const Duration(minutes: 3));
    if (r.status != 200) throw StateError('account $action ${r.status}');
  }

  static Future<void> closeCouple(SupabaseClient db) async {
    await _server(db, 'close');
    await wipeLocal();
  }

  static Future<void> deleteAccount(SupabaseClient db) async {
    await _server(db, 'delete');
    await wipeLocal(everything: true);
    await AppLock.instance.removePin(); // plus de code FouLove pour un compte qui n'existe plus
    try {
      await db.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }

  /// L'autre a fermé la bulle : on efface ce qui en reste ici, et notre sauvegarde (devenue inutile) sur R2.
  static Future<void> forgetEndedCouple(SupabaseClient db) async {
    try {
      await db.functions.invoke('media', body: {'action': 'backup_delete'}).timeout(const Duration(seconds: 30));
    } catch (e) {
      if (kDebugMode) debugPrint('[FOULOVE] sauvegarde à retirer : $e');
    }
    await wipeLocal();
  }

  /// Remet ce téléphone à zéro : base chiffrée, fichiers chiffrés, clés et rappels. `everything` : aussi le code
  /// FouLove, le thème et la session (suppression du compte).
  static Future<void> wipeLocal({bool everything = false}) async {
    deviceClose();
    final dir = await getApplicationSupportDirectory();
    for (final name in ['foulove.db', 'foulove.db-wal', 'foulove.db-shm', 'foulove.db-journal']) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) await f.delete();
    }
    final media = Directory('${dir.path}/media');
    if (await media.exists()) await media.delete(recursive: true);
    await BackupService.instance.forget();
    await Reminders.cancelAll();
    if (everything) {
      await _store.deleteAll();
    } else {
      for (final k in _coupleKeys) {
        await _store.delete(key: k);
      }
    }
  }
}
