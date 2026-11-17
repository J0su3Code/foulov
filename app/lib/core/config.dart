/// Configuration fournie à la compilation : `flutter run --dart-define-from-file=dart_defines.local.json`.
/// Ce sont des identifiants publics (on les retrouve dans toute app publiée) ; aucun secret n'est jamais
/// embarqué dans l'app. Modèle du fichier : `dart_defines.example.json`.
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Client OAuth « Web » créé par Firebase : audience des jetons Google acceptés par Supabase.
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Échoue tôt et clairement si l'app a été compilée sans sa configuration.
  static void check() {
    final missing = <String>[
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabasePublishableKey.isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
      if (googleWebClientId.isEmpty) 'GOOGLE_WEB_CLIENT_ID',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Configuration manquante : ${missing.join(', ')}. '
        'Lance l\'app avec --dart-define-from-file=dart_defines.local.json.',
      );
    }
  }
}
