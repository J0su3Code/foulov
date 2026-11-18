import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/secure_session_storage.dart';
import 'features/auth/auth_service.dart';
import 'features/auth/login_screen.dart';
import 'features/couple/couple_screens.dart';
import 'features/couple/couple_service.dart';
import 'features/intro/intro_screen.dart';
import 'features/lock/app_lock.dart';
import 'src/rust/frb_generated.dart';
import 'theme/foulov_theme.dart';
import 'theme/theme_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Charge le cœur cryptographique Rust (libsignal, chiffrement des fichiers, base locale chiffrée).
  await RustLib.init();
  AppConfig.check();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
  );
  await AppLock.instance.init();
  await ThemeModeSetting.instance.load();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(FouLovApp(auth: AuthService(Supabase.instance.client)));
}

class FouLovApp extends StatelessWidget {
  const FouLovApp({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ThemeModeSetting.instance,
      builder: (context, mode, _) => MaterialApp(
        title: 'FouLove',
        debugShowCheckedModeBanner: false,
        theme: FouLovTheme.jour,
        darkTheme: FouLovTheme.nuit,
        themeMode: mode,
        // Composants système en français (calendrier, menus Copier/Coller…).
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // Le verrou recouvre tout l'écran (navigation comprise), seulement quand quelqu'un est connecté.
        builder: (context, child) => LockGate(active: auth.session != null, child: child ?? const SizedBox()),
        home: _AuthGate(auth: auth),
      ),
    );
  }
}

/// Sans session : intro puis connexion. Avec session : l'espace du couple.
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
              onStart: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LoginScreen(auth: auth))),
              onJoin: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LoginScreen(auth: auth))),
            ),
          );
        }
        // Connecté : on ferme l'écran de connexion resté au-dessus, puis on oriente vers l'espace du couple.
        WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).popUntil((r) => r.isFirst));
        return CoupleGate(
          key: ValueKey(auth.session?.user.id),
          auth: auth,
          couple: CoupleService(Supabase.instance.client),
        );
      },
    );
  }
}
