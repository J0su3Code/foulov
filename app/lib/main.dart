import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/secure_session_storage.dart';
import 'features/auth/auth_service.dart';
import 'features/auth/login_screen.dart';
import 'features/intro/intro_screen.dart';
import 'src/rust/frb_generated.dart';
import 'theme/foulov_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Charge le cœur cryptographique Rust (libsignal, chiffrement des fichiers).
  await RustLib.init();
  AppConfig.check();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(FouLovApp(auth: AuthService(Supabase.instance.client)));
}

class FouLovApp extends StatelessWidget {
  const FouLovApp({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FouLove',
      debugShowCheckedModeBanner: false,
      theme: FouLovTheme.jour,
      darkTheme: FouLovTheme.nuit,
      themeMode: ThemeMode.system,
      home: _AuthGate(auth: auth),
    );
  }
}

/// Sans session : intro puis connexion. Avec session : l'espace du couple (appairage à venir).
class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: auth.changes,
      builder: (context, _) {
        if (auth.session == null) {
          return Builder(
            builder: (context) => IntroScreen(
              onStart: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LoginScreen(auth: auth))),
              onJoin: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LoginScreen(auth: auth))),
            ),
          );
        }
        // Connecté : on ferme l'écran de connexion resté au-dessus.
        WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).popUntil((r) => r.isFirst));
        return _SignedIn(auth: auth);
      },
    );
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final provider = auth.session?.user.appMetadata['provider'] as String? ?? 'email';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.verified_user_outlined, size: 48, color: t.colorScheme.secondary),
              const SizedBox(height: 16),
              Text('Tu es connecté.', style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Connexion par ${provider == 'google' ? 'Google' : 'code e-mail'}. Prochaine étape : créer votre espace '
                'ou rejoindre celui de ton partenaire.',
                style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              TextButton(onPressed: auth.signOut, child: const Text('Se déconnecter')),
            ],
          ),
        ),
      ),
    );
  }
}
