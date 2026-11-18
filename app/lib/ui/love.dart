import 'dart:math';

import 'package:flutter/material.dart';

/// Éléments vivants de FouLove : petits cœurs qui flottent, cœur qui bat, deux rubans qui dessinent un cœur,
/// pluie de cœurs.
/// Tous respectent « réduire les animations » du système (ils s'affichent alors immobiles).

bool _reduce(BuildContext c) => MediaQuery.maybeDisableAnimationsOf(c) ?? false;

// ===================================================================== cœurs flottants

/// Arrière-plan doux : dégradé et petits cœurs qui montent lentement, comme des bulles.
class LoveBackground extends StatefulWidget {
  const LoveBackground({super.key, required this.child, this.count = 16});

  final Widget child;
  final int count;

  @override
  State<LoveBackground> createState() => _LoveBackgroundState();
}

class _LoveBackgroundState extends State<LoveBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_reduce(context)) _c.stop();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [cs.surface, Color.lerp(cs.surface, cs.secondary, .10)!]
              : [cs.surface, Color.lerp(cs.surface, cs.secondary, .16)!],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: RepaintBoundary(child: CustomPaint(painter: _HeartsPainter(_c, widget.count, cs.secondary, dark))),
          ),
          widget.child,
        ],
      ),
    );
  }
}

/// Petit cœur centré sur l'origine, de hauteur ~18.
Path heartPath([double s = 1]) => Path()
  ..moveTo(0, 7 * s)
  ..cubicTo(-10 * s, 0, -9 * s, -10 * s, 0, -5 * s)
  ..cubicTo(9 * s, -10 * s, 10 * s, 0, 0, 7 * s)
  ..close();

class _HeartsPainter extends CustomPainter {
  _HeartsPainter(this.anim, this.count, this.color, this.dark) : super(repaint: anim);

  final Animation<double> anim;
  final int count;
  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Random(7);
    for (var i = 0; i < count; i++) {
      final speed = .6 + r.nextDouble() * .8;
      final phase = r.nextDouble();
      final x0 = r.nextDouble() * size.width;
      final scale = .55 + r.nextDouble() * .8;
      final t = (anim.value * speed + phase) % 1.0;
      // Ils montent doucement en se balançant, et s'estompent en haut comme en bas.
      final y = size.height + 30 - t * (size.height + 60);
      final x = x0 + sin(t * pi * 3 + i) * 18;
      final a = (dark ? .18 : .24) * sin(t * pi);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(sin(t * pi * 2 + i) * .35);
      canvas.scale(scale);
      canvas.drawPath(heartPath(), Paint()..color = color.withValues(alpha: a));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _HeartsPainter old) => old.color != color || old.count != count;
}

// ===================================================================== cœur qui bat

/// Cœur qui bat (lub-dub) avec des ondes qui s'éloignent. [size] : diamètre du cœur.
class BeatingHeart extends StatefulWidget {
  const BeatingHeart({super.key, this.size = 72, this.color});

  final double size;
  final Color? color;

  @override
  State<BeatingHeart> createState() => _BeatingHeartState();
}

class _BeatingHeartState extends State<BeatingHeart> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Deux battements rapprochés puis un repos, comme un vrai cœur.
  double _beat(double t) {
    double pulse(double c, double w) => exp(-pow((t - c) / w, 2).toDouble());
    return 1 + .14 * pulse(.12, .05) + .09 * pulse(.30, .05);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.secondary;
    if (_reduce(context)) _c.stop();
    return SizedBox(
      width: widget.size * 2.4,
      height: widget.size * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var k = 0; k < 2; k++)
                Builder(
                  builder: (context) {
                    final rt = (t + k * .5) % 1.0;
                    return Container(
                      width: widget.size * (1 + rt * 1.3),
                      height: widget.size * (1 + rt * 1.3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withValues(alpha: (1 - rt) * .45), width: 2),
                      ),
                    );
                  },
                ),
              Transform.scale(
                scale: _beat(t),
                child: Icon(
                  Icons.favorite_rounded,
                  size: widget.size,
                  color: color,
                  shadows: [Shadow(color: color.withValues(alpha: .5), blurRadius: 24)],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ===================================================================== deux rubans en cœur

/// Deux rubans (rose et or) partent du même point, s'écartent et se rejoignent en dessinant un cœur ;
/// une étincelle jaillit là où ils se retrouvent, et un petit cœur plein palpite au centre.
class EntwinedHeart extends StatefulWidget {
  const EntwinedHeart({super.key, this.size = 220});

  final double size;

  @override
  State<EntwinedHeart> createState() => _EntwinedHeartState();
}

class _EntwinedHeartState extends State<EntwinedHeart> with TickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..forward();
  late final AnimationController _sway = AnimationController(vsync: this, duration: const Duration(seconds: 5))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _grow.dispose();
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_reduce(context)) {
      _grow.value = 1;
      _sway.stop();
    }
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _EntwinedPainter(
          Listenable.merge([_grow, _sway]),
          () => Curves.easeInOutCubic.transform(_grow.value),
          () => _sway.value,
          stemA: cs.primary,
          stemB: cs.tertiary,
          petal: cs.secondary,
          core: Color.lerp(cs.tertiary, Colors.white, .5)!,
        ),
      ),
    );
  }
}

class _EntwinedPainter extends CustomPainter {
  _EntwinedPainter(
    Listenable l,
    this.grow,
    this.sway, {
    required this.stemA,
    required this.stemB,
    required this.petal,
    required this.core,
  }) : super(repaint: l);

  final double Function() grow;
  final double Function() sway;
  final Color stemA, stemB, petal, core;

  // Courbe en cœur (paramétrique classique), parcourue du bas vers le haut de chaque côté.
  Offset _heart(double s, double side, Size size) {
    final t = pi * (1 - s) * side; // s=0 : pointe basse, s=1 : creux du haut
    final x = 16 * pow(sin(t), 3);
    final y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t);
    final k = size.width / 38;
    return Offset(size.width / 2 + x * k, size.height * .52 - y * k);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = grow();
    final w = (sway() - .5) * 2;
    for (final (side, color) in [(-1.0, stemA), (1.0, stemB)]) {
      final path = Path();
      const n = 90;
      for (var i = 0; i <= (n * g).round(); i++) {
        final s = i / n;
        final p = _heart(s, side, size) + Offset(w * 2 * s, 0);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .022
          ..strokeCap = StrokeCap.round,
      );
    }
    // Quand les deux rubans se rejoignent en haut : une petite étincelle, puis un cœur plein qui palpite doucement.
    final bloom = ((g - .82) / .18).clamp(0.0, 1.0);
    if (bloom > 0) {
      final c = _heart(1, 1, size);
      final b = Curves.easeOutBack.transform(bloom);
      canvas.drawCircle(c, size.width * .16 * b, Paint()..color = petal.withValues(alpha: .16 * bloom));
      for (var i = 0; i < 8; i++) {
        final a = i / 8 * 2 * pi + w * .2;
        final r0 = size.width * .05 * b, r1 = size.width * (.09 + (i.isEven ? .03 : 0)) * b;
        canvas.drawLine(
          c + Offset(cos(a), sin(a)) * r0,
          c + Offset(cos(a), sin(a)) * r1,
          Paint()
            ..color = core.withValues(alpha: .9 * bloom)
            ..strokeWidth = size.width * .012
            ..strokeCap = StrokeCap.round,
        );
      }
      // Le cœur plein, au centre du grand cœur dessiné.
      final center = Offset(size.width / 2, size.height * .5);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(size.width / 70 * b * (1 + .03 * w));
      canvas.drawPath(heartPath(), Paint()..color = petal.withValues(alpha: .9 * bloom));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ===================================================================== pluie de cœurs

/// Pluie de cœurs jouée une fois (célébration).
class HeartBurst extends StatefulWidget {
  const HeartBurst({super.key});

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<HeartBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduce(context)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BurstPainter(_c, [cs.secondary, Color.lerp(cs.secondary, Colors.white, .4)!, cs.tertiary]),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.anim, this.colors) : super(repaint: anim);

  final Animation<double> anim;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Random(3);
    final t = anim.value;
    final origin = Offset(size.width / 2, size.height * .38);
    for (var i = 0; i < 90; i++) {
      final ang = -pi / 2 + (r.nextDouble() - .5) * pi * 1.6;
      final v = 380 + r.nextDouble() * 520;
      final spin = (r.nextDouble() - .5) * 14;
      final drift = (r.nextDouble() - .5) * 60;
      final tt = t * 3.2;
      // Projection puis chute ralentie, comme des confettis légers.
      final p =
          origin +
          Offset(
            cos(ang) * v * (1 - exp(-tt * 1.6)) / 1.6 + sin(tt * 2 + i) * drift,
            sin(ang) * v * (1 - exp(-tt * 1.6)) / 1.6 + 70 * tt * tt,
          );
      final a = (1 - t).clamp(0.0, 1.0);
      if (a <= 0) continue;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(spin * t);
      final s = .7 + r.nextDouble() * .9;
      canvas.scale(s);
      canvas.drawPath(heartPath(.8), Paint()..color = colors[i % colors.length].withValues(alpha: a));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => false;
}
