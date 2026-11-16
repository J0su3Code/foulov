import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/intro/intro_screen.dart';
import 'src/rust/frb_generated.dart';
import 'theme/foulov_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Charge le cœur cryptographique Rust (libsignal, chiffrement des fichiers).
  await RustLib.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const FouLovApp());
}

class FouLovApp extends StatelessWidget {
  const FouLovApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FouLove',
      debugShowCheckedModeBanner: false,
      theme: FouLovTheme.jour,
      darkTheme: FouLovTheme.nuit,
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) => IntroScreen(
          // Les parcours « créer notre espace » et « rejoindre » sont la prochaine étape du développement.
          onStart: () => _soon(context, 'Création de votre espace'),
          onJoin: () => _soon(context, 'Rejoindre avec un code'),
        ),
      ),
    );
  }

  static void _soon(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what : en cours de construction.')));
  }
}
