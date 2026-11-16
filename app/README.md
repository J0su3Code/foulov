# App FouLove (Flutter)

## Lancer

```bash
flutter run --dart-define-from-file=dart_defines.local.json
```

`dart_defines.local.json` (hors git) suit le modèle `dart_defines.example.json`. Il ne contient que des identifiants
publics : URL et clé publiable Supabase, clients OAuth Google. Aucun secret n'est jamais embarqué dans l'app.

## Fichiers Firebase (hors git)

Firebase sert uniquement à fournir les clients OAuth Google et, plus tard, les notifications (pas de firebase_auth).

```bash
firebase --project foulove-app apps:sdkconfig ANDROID <app-id-android> -o android/app/google-services.json
firebase --project foulove-app apps:sdkconfig IOS <app-id-ios> -o ios/Runner/GoogleService-Info.plist
```

Chaque machine qui compile l'app doit enregistrer l'empreinte SHA de sa clé de signature :
`firebase --project foulove-app apps:android:sha:create <app-id-android> <sha1>`.

## Connexion

- Google : `google_sign_in` → jeton d'identité → `supabase.auth.signInWithIdToken` (voir `lib/features/auth/auth_service.dart`).
- Code par e-mail : 8 chiffres, valable 10 minutes.
- La session est rangée dans le Keystore Android ou le Keychain iOS (`lib/core/secure_session_storage.dart`).

## Tests

```bash
flutter test                                   # tests unitaires
flutter test integration_test -d <appareil>    # cœur Rust sur un vrai téléphone ou un émulateur
```
