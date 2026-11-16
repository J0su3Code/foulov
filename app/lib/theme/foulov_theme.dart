import 'package:flutter/material.dart';

/// Couleurs de FouLov.
/// Jour : « Jardin ». Nuit : « Nocturne ».
/// La police est celle du système (Roboto sur Android, San Francisco sur iOS) : on ne la surcharge pas.
abstract final class FouLovColors {
  // Splash natif et début de l'intro : doivent rester identiques à
  // flutter_native_splash.yaml et animation/export_app_assets.sh.
  static const splashDay = Color(0xFF0C2219);
  static const splashNight = Color(0xFF0A0710);

  // Jardin (jour)
  static const brume = Color(0xFFEEF1E8);
  static const sapin = Color(0xFF10291F);
  static const mousse = Color(0xFF3E6B4E);
  static const petale = Color(0xFFF29BB8);
  static const pollen = Color(0xFFF2C94C);
  static const ligneJour = Color(0xFFDCE3D6);
  static const texteDiscretJour = Color(0xFF5D7266);

  // Nocturne (nuit)
  static const nuit = Color(0xFF0A0710);
  static const velours = Color(0xFF1A1322);
  static const velours2 = Color(0xFF21182A);
  static const lueur = Color(0xFFFF9E7A);
  static const braise = Color(0xFFFF5C8A);
  static const champagne = Color(0xFFF6E6CF);
  static const ligneNuit = Color(0xFF2A2033);
  static const texteNuit = Color(0xFFF3EEF6);
  static const texteDiscretNuit = Color(0xFF9A8FA8);
}

abstract final class FouLovTheme {
  static ThemeData get jour => _build(
        ColorScheme(
          brightness: Brightness.light,
          primary: FouLovColors.sapin,
          onPrimary: FouLovColors.brume,
          secondary: FouLovColors.petale,
          onSecondary: FouLovColors.sapin,
          tertiary: FouLovColors.pollen,
          onTertiary: FouLovColors.sapin,
          error: const Color(0xFFB3261E),
          onError: Colors.white,
          surface: FouLovColors.brume,
          onSurface: FouLovColors.sapin,
          onSurfaceVariant: FouLovColors.texteDiscretJour,
          surfaceContainer: Colors.white,
          outline: FouLovColors.ligneJour,
        ),
      );

  static ThemeData get nuit => _build(
        ColorScheme(
          brightness: Brightness.dark,
          primary: FouLovColors.lueur,
          onPrimary: const Color(0xFF2A0B16),
          secondary: FouLovColors.braise,
          onSecondary: const Color(0xFF2A0B16),
          tertiary: FouLovColors.champagne,
          onTertiary: FouLovColors.nuit,
          error: const Color(0xFFFFB4AB),
          onError: const Color(0xFF690005),
          surface: FouLovColors.nuit,
          onSurface: FouLovColors.texteNuit,
          onSurfaceVariant: FouLovColors.texteDiscretNuit,
          surfaceContainer: FouLovColors.velours,
          outline: FouLovColors.ligneNuit,
        ),
      );

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size.fromHeight(44),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
