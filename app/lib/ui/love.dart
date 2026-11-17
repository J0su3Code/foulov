import 'dart:math';

import 'package:flutter/material.dart';

/// Éléments vivants de FouLove : pétales qui flottent, cœur qui bat, tiges qui s'enlacent, pluie de pétales.
/// Tous respectent « réduire les animations » du système (ils s'affichent alors immobiles).

bool _reduce(BuildContext c) => MediaQuery.maybeDisableAnimationsOf(c) ?? false;

// ===================================================================== pétales flottants

/// Arrière-plan doux : dégradé et pétales qui descendent lentement en tournoyant.
class PetalBackground extends StatefulWidget {
  const PetalBackground({super.key, required this.child, this.count = 16});

  final Widget child;
  final int count;

  @override
  State<PetalBackground> createState() => _PetalBackgroundState();
}

class _PetalBackgroundState extends State<PetalBackground> with SingleTickerProviderStateMixin {
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
            child: RepaintBoundary(
              child: CustomPaint(painter: _PetalsPainter(_c, widget.count, cs.secondary, dark)),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _PetalsPainter extends CustomPainter {
  _PetalsPainter(this.anim, this.count, this.color, this.dark) : super(repaint: anim);

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
      final y = -30 + t * (size.height + 60);
      final x = x0 + sin(t * pi * 4 + i) * 22;
      final a = (dark ? .22 : .30) * (0.4 + 0.6 * sin(t * pi));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * pi * 3 + i);
      canvas.scale(scale);
      final p = Path()
        ..moveTo(0, 0)
        ..cubicTo(7, -4, 8, -14, 0, -18)
        ..cubicTo(-8, -14, -7, -4, 0, 0);
      canvas.drawPath(p, Paint()..color = color.withValues(alpha: a));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PetalsPainter old) => old.color != color || old.count != count;
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

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
                Builder(builder: (context) {
                  final rt = (t + k * .5) % 1.0;
                  return Container(
                    width: widget.size * (1 + rt * 1.3),
                    height: widget.size * (1 + rt * 1.3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withValues(alpha: (1 - rt) * .45), width: 2),
                    ),
                  );
                }),
              Transform.scale(
                scale: _beat(t),
                child: Icon(Icons.favorite_rounded, size: widget.size, color: color, shadows: [
                  Shadow(color: color.withValues(alpha: .5), blurRadius: 24),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ===================================================================== tiges enlacées en cœur

/// Deux tiges partent du même point, s'écartent et se rejoignent en dessinant un cœur ;
/// des feuilles apparaissent, une fleur éclot en haut.
class EntwinedHeart extends StatefulWidget {
  const EntwinedHeart({super.key, this.size = 220});

  final double size;

  @override
  State<EntwinedHeart> createState() => _EntwinedHeartState();
}

class _EntwinedHeartState extends State<EntwinedHeart> with TickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  late final AnimationController _sway = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);

  @override
  void dispose() {
    _grow.dispose();
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
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
          stemA: dark ? const Color(0xFF5FA79A) : const Color(0xFF3E6B4E),
          stemB: dark ? const Color(0xFF8CCBB5) : const Color(0xFF7DB37A),
          petal: cs.secondary,
          core: dark ? const Color(0xFFF6E6CF) : const Color(0xFFF2C94C),
        ),
      ),
    );
  }
}

class _EntwinedPainter extends CustomPainter {
  _EntwinedPainter(Listenable l, this.grow, this.sway, {required this.stemA, required this.stemB, required this.petal, required this.core})
      : super(repaint: l);

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
      // Feuilles le long de la tige.
      for (final s in [.22, .45, .68]) {
        final lg = ((g - s) / .15).clamp(0.0, 1.0);
        if (lg <= 0) continue;
        final p = _heart(s, side, size);
        final q = _heart(s + .01, side, size);
        final ang = atan2(q.dy - p.dy, q.dx - p.dx) + (side > 0 ? -1.1 : 1.1);
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(ang + w * .05);
        canvas.scale(Curves.easeOutBack.transform(lg) * size.width / 220);
        final leaf = Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(10, -9, 24, 0)
          ..quadraticBezierTo(10, 8, 0, 0);
        canvas.drawPath(leaf, Paint()..color = color.withValues(alpha: .95));
        canvas.restore();
      }
    }
    // Fleur au creux du cœur, quand les deux tiges se rejoignent.
    final bloom = ((g - .82) / .18).clamp(0.0, 1.0);
    if (bloom > 0) {
      final c = _heart(1, 1, size);
      final b = Curves.easeOutBack.transform(bloom);
      final r = size.width * .07 * b;
      canvas.drawCircle(c, r * 2.6, Paint()..color = petal.withValues(alpha: .18 * bloom));
      for (var i = 0; i < 6; i++) {
        final a = i / 6 * 2 * pi + w * .1;
        canvas.drawOval(
          Rect.fromCenter(center: c + Offset(cos(a), sin(a)) * r, width: r * 1.6, height: r * 1.05),
          Paint()..color = Color.lerp(petal, Colors.white, i.isEven ? 0 : .25)!,
        );
      }
      canvas.drawCircle(c, r * .55, Paint()..color = core);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ===================================================================== pluie de pétales

/// Pluie de pétales jouée une fois (célébration).
class PetalBurst extends StatefulWidget {
  const PetalBurst({super.key});

  @override
  State<PetalBurst> createState() => _PetalBurstState();
}

class _PetalBurstState extends State<PetalBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..forward();

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
      // Projection puis chute ralentie, comme des pétales légers.
      final p = origin +
          Offset(cos(ang) * v * (1 - exp(-tt * 1.6)) / 1.6 + sin(tt * 2 + i) * drift,
              sin(ang) * v * (1 - exp(-tt * 1.6)) / 1.6 + 70 * tt * tt);
      final a = (1 - t).clamp(0.0, 1.0);
      if (a <= 0) continue;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(spin * t);
      final s = .7 + r.nextDouble() * .9;
      canvas.scale(s);
      final path = Path()
        ..moveTo(0, 0)
        ..cubicTo(6, -4, 7, -12, 0, -15)
        ..cubicTo(-7, -12, -6, -4, 0, 0);
      canvas.drawPath(path, Paint()..color = colors[i % colors.length].withValues(alpha: a));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => false;
}
