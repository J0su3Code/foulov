import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Range la session Supabase (jetons d'accès et de rafraîchissement) dans le coffre du système :
/// Android Keystore, iOS Keychain (accessible seulement sur cet appareil, après le premier déverrouillage).
/// Par défaut, supabase_flutter utiliserait les préférences de l'app, non chiffrées.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage();

  static const _key = 'foulov.supabase.session';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) => _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
