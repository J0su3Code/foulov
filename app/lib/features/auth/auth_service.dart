import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';

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
  Future<void> sendEmailCode(String email) =>
      _supabase.auth.signInWithOtp(email: email.trim(), shouldCreateUser: true);

  /// Vérifie le code reçu par e-mail et ouvre la session.
  Future<User?> verifyEmailCode(String email, String code) async {
    final res = await _supabase.auth.verifyOTP(type: OtpType.email, email: email.trim(), token: code.trim());
    return res.user;
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _supabase.auth.signOut();
  }
}
