import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/foulov_theme.dart';
import '../space/space_service.dart';

// =====================================================================================================================
// Palettes. Les index voyagent entre les deux téléphones : ne jamais réordonner, seulement ajouter à la fin.
// =====================================================================================================================

/// Couleurs des bulles (« ta couleur ») : un dégradé de deux tons.
abstract final class BubbleColors {
  static const List<(String, Color, Color)> all = [
    ('Framboise', Color(0xFFE8417A), Color(0xFFC2185B)),
    ('Rose', Color(0xFFFF7A9C), Color(0xFFE8417A)),
    ('Pêche', Color(0xFFF39C6B), Color(0xFFE8417A)),
    ('Soleil', Color(0xFFF5B342), Color(0xFFE07A2E)),
    ('Lilas', Color(0xFFB06AD9), Color(0xFF7B3FA8)),
    ('Prune', Color(0xFF9B59B6), Color(0xFF6C3483)),
    ('Nuit bleue', Color(0xFF5C7CFA), Color(0xFF3B4FC4)),
    ('Lagon', Color(0xFF2EC4B6), Color(0xFF1A7F8E)),
    ('Menthe', Color(0xFF3FAE7A), Color(0xFF237A55)),
    ('Ardoise', Color(0xFF6D6875), Color(0xFF3D3842)),
    ('Corail', Color(0xFFFF6F61), Color(0xFFE0457B)),
    ('Cerise', Color(0xFFD7263D), Color(0xFF9E1946)),
    ('Aurore', Color(0xFFFF9A8B), Color(0xFFFF6A88)),
    ('Améthyste', Color(0xFF8E2DE2), Color(0xFF4A00E0)),
    ('Océan', Color(0xFF00B4DB), Color(0xFF0083B0)),
    ('Or rose', Color(0xFFE6B5A6), Color(0xFFB76E79)),
  ];

  static (Color, Color) of(int? i) {
    final c = all[(i ?? 0).clamp(0, all.length - 1)];
    return (c.$2, c.$3);
  }
}

/// Fonds en dégradé libre à 4 couleurs (comme Telegram), en version jour et nuit.
abstract final class Wallpapers {
  static const List<(String, List<Color>, List<Color>)> all = [
    (
      'Douceur',
      [Color(0xFFFFF1F3), Color(0xFFFFE3EA), Color(0xFFFFF6EE), Color(0xFFF8E6F4)],
      [Color(0xFF1A0F1A), Color(0xFF261526), Color(0xFF1C1020), Color(0xFF2A1428)],
    ),
    (
      'Pêche',
      [Color(0xFFFFD6C9), Color(0xFFFFE9D6), Color(0xFFFFC8D6), Color(0xFFFFF0E2)],
      [Color(0xFF2E1612), Color(0xFF3A1E1E), Color(0xFF2B1220), Color(0xFF3C2418)],
    ),
    (
      'Crépuscule',
      [Color(0xFFFFC3D8), Color(0xFFE3D0FF), Color(0xFFFFE0C7), Color(0xFFD6C6FF)],
      [Color(0xFF2C1A3D), Color(0xFF4A1F45), Color(0xFF231337), Color(0xFF5A2440)],
    ),
    (
      'Velours',
      [Color(0xFFF3C4D9), Color(0xFFE2B4D2), Color(0xFFF6D8E4), Color(0xFFD9A7C7)],
      [Color(0xFF3A1230), Color(0xFF5E1A44), Color(0xFF2A0E26), Color(0xFF7A2E5A)],
    ),
    (
      'Lagon',
      [Color(0xFFCDEFEA), Color(0xFFD8E4FF), Color(0xFFE6F7F1), Color(0xFFC9DCF7)],
      [Color(0xFF0B2A3C), Color(0xFF14505A), Color(0xFF0E1E36), Color(0xFF1B4A6B)],
    ),
    (
      'Miel',
      [Color(0xFFFFEBC2), Color(0xFFFFD9C2), Color(0xFFFFF3D6), Color(0xFFFFE0A8)],
      [Color(0xFF2A1E10), Color(0xFF3A2414), Color(0xFF241808), Color(0xFF4A3014)],
    ),
    (
      'Brume',
      [Color(0xFFF1EEF4), Color(0xFFFBF3F1), Color(0xFFEDEAF2), Color(0xFFF7EFF3)],
      [Color(0xFF16141C), Color(0xFF221C26), Color(0xFF121016), Color(0xFF1E1A24)],
    ),
    (
      'Lavande',
      [Color(0xFFE6DBFF), Color(0xFFF3E3FF), Color(0xFFDCD3FB), Color(0xFFFBE4F2)],
      [Color(0xFF1E1638), Color(0xFF2E1F4E), Color(0xFF171230), Color(0xFF3A2252)],
    ),
    (
      'Aurore',
      [Color(0xFFFFD1D1), Color(0xFFFFE8C4), Color(0xFFFFC2E2), Color(0xFFE7D8FF)],
      [Color(0xFF3A1420), Color(0xFF3E2A18), Color(0xFF3A1236), Color(0xFF26193E)],
    ),
    (
      'Cerisier',
      [Color(0xFFFFE4EC), Color(0xFFFFCFDF), Color(0xFFFFF5F8), Color(0xFFF9D5E5)],
      [Color(0xFF2A0E1A), Color(0xFF3E1426), Color(0xFF200A14), Color(0xFF4A1A30)],
    ),
    (
      'Menthe',
      [Color(0xFFDDF5E6), Color(0xFFEAF7DE), Color(0xFFD3EFEA), Color(0xFFF1FAE8)],
      [Color(0xFF0E2418), Color(0xFF16321F), Color(0xFF0A1E1A), Color(0xFF1C3A26)],
    ),
    (
      'Nuit étoilée',
      [Color(0xFFDDE3FF), Color(0xFFE9DDFF), Color(0xFFD5E0FA), Color(0xFFF0E4FF)],
      [Color(0xFF0A0E26), Color(0xFF1A1440), Color(0xFF050818), Color(0xFF241A4A)],
    ),
  ];

  static List<Color> colors(int i, bool night) {
    final w = all[i.clamp(0, all.length - 1)];
    return night ? w.$3 : w.$2;
  }
}

/// Motifs dessinés par-dessus le fond.
abstract final class Patterns {
  static const List<String> all = [
    'Aucun',
    'Cœurs',
    'Étoiles et lunes',
    'Mots doux',
    'Musique',
    'Confettis',
    'Pois',
    'Pour toujours',
  ];
}

/// Thèmes complets : fond, motif, intensité, couleur et style des bulles, forme. Un toucher, et tout s'accorde.
class ChatTheme {
  const ChatTheme(
    this.name, {
    required this.wallpaper,
    required this.pattern,
    this.opacity = 9,
    required this.color,
    this.style = 0,
    this.shape = 2,
  });

  final String name;
  final int wallpaper, pattern, opacity, color, style, shape;

  static const all = [
    ChatTheme('Douce romance', wallpaper: 0, pattern: 1, color: 0),
    ChatTheme('Coucher de soleil', wallpaper: 1, pattern: 3, color: 2, opacity: 8),
    ChatTheme('Nuit étoilée', wallpaper: 11, pattern: 2, color: 13, opacity: 12),
    ChatTheme('Lavande', wallpaper: 7, pattern: 6, color: 4, style: 2, opacity: 7),
    ChatTheme('Velours', wallpaper: 3, pattern: 7, color: 11, opacity: 8),
    ChatTheme('Lagon', wallpaper: 4, pattern: 4, color: 14, style: 1, opacity: 8),
    ChatTheme('Cerisier', wallpaper: 9, pattern: 5, color: 1, style: 2, opacity: 10, shape: 1),
    ChatTheme('Classique', wallpaper: 6, pattern: 0, color: 9, style: 3, shape: 1),
  ];
}

// =====================================================================================================================
// Bulles
// =====================================================================================================================

/// Apparence des bulles, choisie à deux (« Personnaliser ») et partagée chiffrée.
///
/// - Tes bulles : ta couleur, selon le style (dégradé, uni, verre dépoli, contour).
/// - Ses bulles : neutres, teintées de sa couleur à lui (s'il en a choisi une).
/// - Forme : 0 carrées, 1 arrondies, 2 très douces. Taille du texte : propre à chaque téléphone.
class BubbleLook extends InheritedWidget {
  const BubbleLook({
    super.key,
    required this.shape,
    required this.mine,
    required this.theirs,
    this.style = 0,
    this.textScale = 1,
    required super.child,
  });

  factory BubbleLook.from(SpaceService s, {Key? key, required Widget child}) => BubbleLook(
    key: key,
    shape: s.bubbleShape,
    mine: BubbleColors.of(s.myColor),
    theirs: s.partnerColor == null ? null : BubbleColors.of(s.partnerColor).$1,
    style: s.bubbleStyle,
    textScale: const [.9, 1.0, 1.15][s.textSize],
    child: child,
  );

  final int shape, style;
  final (Color, Color) mine;
  final Color? theirs;
  final double textScale;

  static BubbleLook of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BubbleLook>() ??
      const BubbleLook(shape: 2, mine: (Color(0xFFE8417A), Color(0xFFC2185B)), theirs: null, child: SizedBox());

  Radius get radius => Radius.circular(switch (shape) {
    0 => 8,
    1 => 16,
    _ => 22,
  });

  Radius get tail => Radius.circular(shape == 0 ? 3 : 6);

  /// Taille du texte des messages.
  double get fontSize => 15.5 * textScale;

  Color fg(BuildContext context, bool fromMe) {
    if (!fromMe) return context.love.onTheirBubble;
    return switch (style) {
      2 => context.night ? Colors.white : const Color(0xFF2B1A22),
      3 => context.night ? Color.lerp(mine.$1, Colors.white, .35)! : mine.$2,
      _ => Colors.white,
    };
  }

  BoxDecoration box(BuildContext context, {required bool fromMe, required BorderRadius radius}) {
    final night = context.night;
    if (fromMe) {
      return switch (style) {
        // Uni.
        1 => BoxDecoration(borderRadius: radius, color: mine.$1),
        // Verre dépoli : laiteux, translucide, un liseré clair et une touche de ta couleur.
        2 => BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: night
                ? [Colors.white.withValues(alpha: .16), mine.$1.withValues(alpha: .30)]
                : [Colors.white.withValues(alpha: .78), Color.lerp(Colors.white, mine.$1, .28)!.withValues(alpha: .72)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: night ? .22 : .9)),
          boxShadow: [BoxShadow(color: mine.$2.withValues(alpha: .16), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        // Contour : transparent, bordure à ta couleur.
        3 => BoxDecoration(
          borderRadius: radius,
          color: (night ? Colors.black : Colors.white).withValues(alpha: night ? .25 : .55),
          border: Border.all(color: night ? mine.$1 : mine.$2, width: 1.6),
        ),
        // Dégradé.
        _ => BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [mine.$1, mine.$2]),
          boxShadow: [BoxShadow(color: mine.$2.withValues(alpha: .18), blurRadius: 8, offset: const Offset(0, 2))],
        ),
      };
    }
    final base = context.love.theirBubble;
    return BoxDecoration(
      borderRadius: radius,
      color: theirs == null ? base : Color.lerp(base, theirs, night ? .22 : .12),
      border: Border.all(color: context.cs.outline.withValues(alpha: night ? .6 : 1)),
      boxShadow: night
          ? null
          : [BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 4, offset: const Offset(0, 1))],
    );
  }

  @override
  bool updateShouldNotify(BubbleLook old) =>
      old.shape != shape ||
      old.mine != mine ||
      old.theirs != theirs ||
      old.style != style ||
      old.textScale != textScale;
}

// =====================================================================================================================
// Fond
// =====================================================================================================================

/// Fond de la conversation : dégradé libre à 4 couleurs qui glisse doucement à chaque message envoyé (`bump`),
/// motif dessiné par-dessus, ou votre photo floutée et assombrie à votre goût.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.space, required this.child, this.thumbnail = false});

  final SpaceService space;
  final Widget child;

  /// Petite vignette (choix d'un thème) : pas de photo, motif plus serré.
  final bool thumbnail;

  /// Incrémenté à chaque message envoyé : les couleurs du dégradé changent de place.
  static final step = ValueNotifier<int>(0);
  static void bump() => step.value++;

  @override
  Widget build(BuildContext context) {
    final night = context.night;
    final photo = !thumbnail && space.wallpaper == 'photo' ? space.wallpaperPhoto : null;
    final colors = Wallpapers.colors(int.tryParse(space.wallpaper) ?? 0, night);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photo == null)
          ValueListenableBuilder(
            valueListenable: step,
            builder: (context, s, _) => FreeformGradient(colors: colors, step: thumbnail ? 0 : s),
          )
        else
          FutureBuilder(
            future: space.open(photo.mediaId),
            builder: (context, snap) {
              final bytes = snap.data ?? (photo.media.thumb.isEmpty ? null : photo.media.thumb);
              if (bytes == null) return ColoredBox(color: context.cs.surface);
              final blur = space.photoBlur.toDouble();
              return Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    enabled: blur > 0,
                    imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
                    child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                  ColoredBox(color: Colors.black.withValues(alpha: space.photoDim / 100)),
                ],
              );
            },
          ),
        if (space.pattern > 0 && photo == null)
          RepaintBoundary(
            child: CustomPaint(
              painter: PatternPainter(
                space.pattern,
                (night ? Colors.white : const Color(0xFF3A1A2A)).withValues(alpha: space.patternOpacity / 100),
                scale: thumbnail ? .5 : 1,
              ),
            ),
          ),
        child,
      ],
    );
  }
}

/// Dégradé libre : quatre taches de couleur douces, posées sur 8 positions qui tournent d'un cran à chaque `step`.
class FreeformGradient extends StatelessWidget {
  const FreeformGradient({super.key, required this.colors, this.step = 0});

  final List<Color> colors;
  final int step;

  static const _spots = [
    Alignment(-.8, -.9),
    Alignment(.1, -1.1),
    Alignment(.9, -.6),
    Alignment(1.0, .3),
    Alignment(.7, 1.0),
    Alignment(-.2, 1.1),
    Alignment(-1.0, .6),
    Alignment(-1.1, -.2),
  ];

  @override
  Widget build(BuildContext context) {
    final base = Color.lerp(Color.lerp(colors[0], colors[1], .5), Color.lerp(colors[2], colors[3], .5), .5)!;
    return ColoredBox(
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < 4; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: _spots[(i * 2 + step) % _spots.length],
                  radius: 1.15,
                  colors: [colors[i], colors[i].withValues(alpha: 0)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Motif dessiné en tuiles : petits dessins au trait, placés et tournés « au hasard » (toujours le même hasard).
class PatternPainter extends CustomPainter {
  PatternPainter(this.kind, this.color, {this.scale = 1});

  final int kind;
  final Color color;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (kind <= 0 || color.a == 0) return;
    canvas.clipRect(Offset.zero & size); // les tuiles débordent : on ne dessine que dans le fond
    final tile = 150.0 * scale;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    final r = Random(kind * 7919);
    // Positions dans une tuile : grille 3×3 décalée, pour une répartition régulière mais vivante.
    final spots = [
      for (var gy = 0; gy < 3; gy++)
        for (var gx = 0; gx < 3; gx++)
          (
            Offset(
              (gx + .5 + (r.nextDouble() - .5) * .55) * tile / 3,
              (gy + .5 + (r.nextDouble() - .5) * .55) * tile / 3,
            ),
            (r.nextDouble() - .5) * 1.1,
            .75 + r.nextDouble() * .5,
            r.nextInt(4),
          ),
    ];
    for (var ty = -tile; ty < size.height + tile; ty += tile) {
      final shift = ((ty / tile).round().isOdd ? tile / 2 : 0);
      for (var tx = -tile; tx < size.width + tile; tx += tile) {
        for (final (p, rot, sc, v) in spots) {
          canvas.save();
          canvas.translate(tx + shift + p.dx, ty + p.dy);
          canvas.rotate(rot);
          canvas.scale(sc * scale);
          _glyph(canvas, v, stroke, fill);
          canvas.restore();
        }
      }
    }
  }

  void _glyph(Canvas c, int v, Paint s, Paint f) {
    switch (kind) {
      case 1: // cœurs (plein ou au trait)
        final h = _heart(v == 0 ? 9 : 7);
        c.drawPath(h, v == 3 ? f : s);
      case 2: // étoiles, lunes, scintillements
        switch (v) {
          case 0:
            c.drawPath(_star(8, 3.6), s);
          case 1:
            // Croissant de lune : le disque, moins un disque décalé.
            c.drawPath(
              Path.combine(
                PathOperation.difference,
                Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 8)),
                Path()..addOval(Rect.fromCircle(center: const Offset(4.5, -3), radius: 7)),
              ),
              s,
            );
          case 2:
            c.drawPath(_sparkle(7), s);
          default:
            c.drawCircle(Offset.zero, 1.6, f);
        }
      case 3: // mots doux : enveloppe, cœur, bulle de dialogue, petit « xo »
        switch (v) {
          case 0:
            final rect = Rect.fromCenter(center: Offset.zero, width: 18, height: 12);
            c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), s);
            c.drawPath(
              Path()
                ..moveTo(rect.left, rect.top)
                ..lineTo(0, 1)
                ..lineTo(rect.right, rect.top),
              s,
            );
          case 1:
            c.drawPath(_heart(8), s);
          case 2:
            final b = RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 18, height: 13),
              const Radius.circular(6),
            );
            c.drawRRect(b, s);
            c.drawPath(
              Path()
                ..moveTo(-3, 6.5)
                ..lineTo(-6, 10)
                ..lineTo(0, 6.5),
              s,
            );
          default:
            c.drawPath(
              Path()
                ..moveTo(-8, -4)
                ..lineTo(-2, 4)
                ..moveTo(-2, -4)
                ..lineTo(-8, 4),
              s,
            );
            c.drawCircle(const Offset(5, 0), 4, s);
        }
      case 4: // musique
        switch (v) {
          case 0 || 2:
            c.drawOval(Rect.fromCenter(center: const Offset(-3, 6), width: 7, height: 5), f);
            c.drawLine(const Offset(0.4, 6), const Offset(0.4, -8), s);
            c.drawPath(
              Path()
                ..moveTo(0.4, -8)
                ..quadraticBezierTo(6, -6, 5, -1),
              s,
            );
          case 1:
            c.drawOval(Rect.fromCenter(center: const Offset(-6, 6), width: 6, height: 4.5), f);
            c.drawOval(Rect.fromCenter(center: const Offset(5, 4), width: 6, height: 4.5), f);
            c.drawLine(const Offset(-3.3, 6), const Offset(-3.3, -7), s);
            c.drawLine(const Offset(7.7, 4), const Offset(7.7, -9), s);
            c.drawLine(const Offset(-3.3, -7), const Offset(7.7, -9), s);
          default:
            c.drawPath(_heart(5), s);
        }
      case 5: // confettis
        switch (v) {
          case 0:
            c.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset.zero, width: 10, height: 4),
                const Radius.circular(2),
              ),
              f,
            );
          case 1:
            c.drawPath(
              Path()
                ..moveTo(-8, 0)
                ..cubicTo(-4, -6, 0, 6, 4, 0)
                ..cubicTo(6, -3, 8, -2, 9, 0),
              s,
            );
          case 2:
            c.drawCircle(Offset.zero, 2.4, f);
          default:
            c.drawPath(_star(5, 2.2), f);
        }
      case 6: // pois
        c.drawCircle(Offset.zero, v.isEven ? 3.2 : 1.8, f);
      case 7: // pour toujours : infini, bague, cœurs entrelacés
        switch (v) {
          case 0:
            final p = Path();
            for (var i = 0; i <= 40; i++) {
              final t = i / 40 * 2 * pi;
              final d = 1 + sin(t) * sin(t);
              final pt = Offset(10 * cos(t) / d, 10 * sin(t) * cos(t) / d);
              i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
            }
            c.drawPath(p, s);
          case 1:
            c.drawCircle(const Offset(0, 3), 6.5, s);
            c.drawPath(
              Path()
                ..moveTo(-3, -4)
                ..lineTo(0, -8)
                ..lineTo(3, -4)
                ..close(),
              s,
            );
          case 2:
            c.save();
            c.translate(-3.5, 0);
            c.drawPath(_heart(6), s);
            c.translate(7, 1);
            c.drawPath(_heart(6), s);
            c.restore();
          default:
            c.drawPath(_sparkle(5), s);
        }
    }
  }

  static Path _heart(double r) => Path()
    ..moveTo(0, r * .8)
    ..cubicTo(-r * 1.3, 0, -r * 1.1, -r * 1.2, 0, -r * .55)
    ..cubicTo(r * 1.1, -r * 1.2, r * 1.3, 0, 0, r * .8)
    ..close();

  static Path _star(double ro, double ri) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final a = -pi / 2 + i * pi / 5;
      final r = i.isEven ? ro : ri;
      final pt = Offset(cos(a) * r, sin(a) * r);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  static Path _sparkle(double r) => Path()
    ..moveTo(0, -r)
    ..quadraticBezierTo(0, 0, r, 0)
    ..quadraticBezierTo(0, 0, 0, r)
    ..quadraticBezierTo(0, 0, -r, 0)
    ..quadraticBezierTo(0, 0, 0, -r)
    ..close();

  @override
  bool shouldRepaint(PatternPainter old) => old.kind != kind || old.color != color || old.scale != scale;
}
