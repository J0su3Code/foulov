import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../backup/backup_service.dart';
import '../chat/push_service.dart';

/// Connexion sans mot de passe : Google ou code à usage unique par e-mail.
///
/// Google : même schéma que Lettre Ouverte. Firebase fournit les clients OAuth (google-services.json sur
/// Android), google_sign_in récupère un jeton d'identité, et Supabase ouvre la session avec
/// `signInWithIdToken`. firebase_auth n'est pas utilisé.
///
/// Rien de personnel n'est écrit dans les journaux (ni e-mail, ni jeton).
class AuthService {
  AuthService(this._supabase);

  final SupabaseClient _supabase;
  bool _googleReady = false;

  Session? get session => _supabase.auth.currentSession;

  // Connexion par code en cours. Pendant qu'on va chercher le code dans ses e-mails, certains téléphones
  // (TECNO, Xiaomi…) ferment l'app pour libérer de la mémoire : au retour, on rouvre directement la saisie du code.
  static const _pendingKey = 'foulov.pending_login';
  static const _pendingFor = Duration(minutes: 10); // durée de vie du code (otp_expiry)

  /// Adresse à laquelle un code a été envoyé il y a moins de 10 minutes, lue au démarrage par [loadPending].
  String? pendingEmail;

  Future<void> loadPending() async {
    try {
      final v = await const FlutterSecureStorage().read(key: _pendingKey);
      final i = v?.lastIndexOf('|') ?? -1;
      if (v == null || i < 0) return;
      final sent = DateTime.fromMillisecondsSinceEpoch(int.parse(v.substring(i + 1)));
      if (DateTime.now().difference(sent) < _pendingFor) {
        pendingEmail = v.substring(0, i);
      } else {
        await clearPending();
      }
    } catch (_) {}
  }

  Future<void> clearPending() async {
    pendingEmail = null;
    try {
      await const FlutterSecureStorage().delete(key: _pendingKey);
    } catch (_) {}
  }

  Stream<AuthState> get changes => _supabase.auth.onAuthStateChange;

  Future<void> _initGoogle() async {
    if (_googleReady) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android : le client « Web » est lu depuis google-services.json (ressource default_web_client_id).
      await GoogleSignIn.instance.initialize();
    } else {
      await GoogleSignIn.instance.initialize(
        clientId: AppConfig.googleIosClientId.isEmpty ? null : AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleWebClientId,
      );
    }
    _googleReady = true;
  }

  /// Ouvre le sélecteur de compte Google puis la session Supabase.
  /// Lève [GoogleSignInException] (annulation, configuration) ou [AuthException] (jeton refusé).
  Future<User?> signInWithGoogle() async {
    await _initGoogle();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'Jeton Google absent : vérifier google-services.json et les empreintes SHA dans Firebase.',
      );
    }
    final res = await _supabase.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
    return res.user;
  }

  /// Envoie un code à usage unique (8 chiffres, valable 10 minutes) à l'adresse indiquée.
  Future<void> sendEmailCode(String email) async {
    await _supabase.auth.signInWithOtp(email: email.trim(), shouldCreateUser: true);
    pendingEmail = email.trim();
    await const FlutterSecureStorage().write(
      key: _pendingKey,
      value: '${email.trim()}|${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// Vérifie le code reçu par e-mail et ouvre la session.
  Future<User?> verifyEmailCode(String email, String code) async {
    final res = await _supabase.auth.verifyOTP(type: OtpType.email, email: email.trim(), token: code.trim());
    await clearPending();
    return res.user;
  }

  Future<void> signOut() async {
    await PushService.unregister(_supabase);
    await BackupService.instance.forget();
    // L'état du couple gardé pour l'ouverture rapide ne doit pas survivre au compte.
    await const FlutterSecureStorage().delete(key: 'foulov.couple_cache');
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _supabase.auth.signOut();
  }
}
