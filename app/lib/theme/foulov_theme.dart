import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Couleurs de FouLove : « une bulle à deux ».
/// Jour : crème et framboise. Nuit : prune profonde, lueurs rose et or.
/// La police est celle du système (Roboto sur Android, San Francisco sur iOS) : on ne la surcharge pas.
abstract final class FouLovColors {
  // Splash natif et début de l'intro : doivent rester identiques à flutter_native_splash.yaml
  // et à animation/export_app_assets.sh (couleur du début de l'intro, mesurée sur la vidéo).
  static const splashDay = Color(0xFFF5EEE8);
  static const splashNight = Color(0xFF0D000E);

  // Jour
  static const creme = Color(0xFFFFF8F5);
  static const blanc = Color(0xFFFFFFFF);
  static const creme2 = Color(0xFFFBEFEE);
  static const ligneJour = Color(0xFFF0E1E1);
  static const encre = Color(0xFF2B1A22);
  static const discretJour = Color(0xFF86707B);
  static const framboise = Color(0xFFD6336C);
  static const roseTendre = Color(0xFFFFE3EA);
  static const or = Color(0xFFE8A93A);

  // Nuit
  static const prune = Color(0xFF140C14);
  static const prune2 = Color(0xFF1B1019);
  static const velours = Color(0xFF221520);
  static const veloursBulle = Color(0xFF2A1A27);
  static const ligneNuit = Color(0xFF33222F);
  static const texteNuit = Color(0xFFFBEFF4);
  static const discretNuit = Color(0xFFB79FB0);
  static const roseNuit = Color(0xFFFF6F9F);
  static const roseNuitSoft = Color(0xFF3A1830);
  static const orNuit = Color(0xFFF5C26B);
}

/// Couleurs propres à FouLove, au-delà du schéma Material : `context.love`.
@immutable
class Love extends ThemeExtension<Love> {
  const Love({
    required this.gold,
    required this.soft,
    required this.surface2,
    required this.ok,
    required this.theirBubble,
    required this.onTheirBubble,
  });

  /// Or chaud : étapes, capsules, anneau des instants.
  final Color gold;

  /// Rose très doux : puces, fonds de sélection.
  final Color soft;

  /// Second fond, un ton sous les cartes.
  final Color surface2;

  /// « En ligne », confirmations.
  final Color ok;

  /// Bulles du partenaire.
  final Color theirBubble;
  final Color onTheirBubble;

  /// Anneau des instants non vus.
  Gradient ring(ColorScheme cs) => SweepGradient(colors: [gold, cs.secondary, cs.primary, gold]);

  static const jour = Love(
    gold: FouLovColors.or,
    soft: FouLovColors.roseTendre,
    surface2: FouLovColors.creme2,
    ok: Color(0xFF2E9B6E),
    theirBubble: FouLovColors.blanc,
    onTheirBubble: FouLovColors.encre,
  );

  static const nuit = Love(
    gold: FouLovColors.orNuit,
    soft: FouLovColors.roseNuitSoft,
    surface2: FouLovColors.prune2,
    ok: Color(0xFF7FE0C2),
    theirBubble: FouLovColors.veloursBulle,
    onTheirBubble: FouLovColors.texteNuit,
  );

  @override
  Love copyWith({Color? gold, Color? soft, Color? surface2, Color? ok, Color? theirBubble, Color? onTheirBubble}) =>
      Love(
        gold: gold ?? this.gold,
        soft: soft ?? this.soft,
        surface2: surface2 ?? this.surface2,
        ok: ok ?? this.ok,
        theirBubble: theirBubble ?? this.theirBubble,
        onTheirBubble: onTheirBubble ?? this.onTheirBubble,
      );

  @override
  Love lerp(Love? other, double t) {
    if (other == null) return this;
    return Love(
      gold: Color.lerp(gold, other.gold, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      theirBubble: Color.lerp(theirBubble, other.theirBubble, t)!,
      onTheirBubble: Color.lerp(onTheirBubble, other.onTheirBubble, t)!,
    );
  }
}

extension LoveContext on BuildContext {
  Love get love => Theme.of(this).extension<Love>()!;
  ColorScheme get cs => Theme.of(this).colorScheme;
  bool get night => Theme.of(this).brightness == Brightness.dark;
}

// Couleurs des bulles, fonds, motifs et thèmes de la conversation : voir features/chat/bubble_look.dart.

/// Fonds des instants texte (index partagé : ne jamais réordonner).
abstract final class MomentStyles {
  static const List<List<Color>> all = [
    [Color(0xFFE8417A), Color(0xFFF39C6B)],
    [Color(0xFF7B3FA8), Color(0xFFE8417A)],
    [Color(0xFF1A7F8E), Color(0xFF5C7CFA)],
    [Color(0xFFE07A2E), Color(0xFFF5B342)],
    [Color(0xFF2C1A3D), Color(0xFF7A2E5A)],
    [Color(0xFF237A55), Color(0xFF2EC4B6)],
  ];

  static List<Color> of(int i) => all[i.clamp(0, all.length - 1)];
}

abstract final class FouLovTheme {
  static ThemeData get jour => _build(
    const ColorScheme(
      brightness: Brightness.light,
      primary: FouLovColors.framboise,
      onPrimary: Colors.white,
      secondary: Color(0xFFFF8FAB),
      onSecondary: FouLovColors.encre,
      tertiary: FouLovColors.or,
      onTertiary: FouLovColors.encre,
      error: Color(0xFFB3261E),
      onError: Colors.white,
      surface: FouLovColors.creme,
      onSurface: FouLovColors.encre,
      onSurfaceVariant: FouLovColors.discretJour,
      surfaceContainer: FouLovColors.blanc,
      surfaceContainerHigh: FouLovColors.blanc,
      surfaceContainerHighest: FouLovColors.creme2,
      outline: FouLovColors.ligneJour,
      outlineVariant: FouLovColors.ligneJour,
      primaryContainer: FouLovColors.roseTendre,
      onPrimaryContainer: FouLovColors.framboise,
    ),
    Love.jour,
  );

  static ThemeData get nuit => _build(
    const ColorScheme(
      brightness: Brightness.dark,
      primary: FouLovColors.roseNuit,
      onPrimary: Color(0xFF2A0815),
      secondary: Color(0xFFFF8FAB),
      onSecondary: Color(0xFF2A0815),
      tertiary: FouLovColors.orNuit,
      onTertiary: FouLovColors.prune,
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: FouLovColors.prune,
      onSurface: FouLovColors.texteNuit,
      onSurfaceVariant: FouLovColors.discretNuit,
      surfaceContainer: FouLovColors.velours,
      surfaceContainerHigh: FouLovColors.veloursBulle,
      surfaceContainerHighest: FouLovColors.veloursBulle,
      outline: FouLovColors.ligneNuit,
      outlineVariant: FouLovColors.ligneNuit,
      primaryContainer: FouLovColors.roseNuitSoft,
      onPrimaryContainer: FouLovColors.roseNuit,
    ),
    Love.nuit,
  );

  static ThemeData _build(ColorScheme scheme, Love love) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      extensions: [love],
      // Transitions douces : retour prédictif d'Android (on voit l'écran précédent pendant le geste), glissé sur iOS.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: love.surface2,
        selectedColor: scheme.primary,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
        secondaryLabelStyle: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w500),
        checkmarkColor: scheme.onPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52), // pleine largeur seulement dans une colonne étirée (pas dans les dialogues)
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(64, 44), // hauteur confortable, largeur selon le contexte
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
