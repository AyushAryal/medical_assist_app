import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/theme_scope.dart';
import 'effects_motion.dart';

/// The glowing, gradient-animated loop drawn where the recogniser is reading —
/// the "circle to search" mark.
///
/// It earns the gradient exception the same way the other effects here do: it
/// signals in-progress machine work (what the scanner is being pointed at), its
/// colour is built from the palette, and it stops and degrades to a static
/// stroke under reduced motion.
///
/// [points] are normalised (0–1) over this widget's box, so the caller does not
/// have to know the display size.
class GlowLasso extends StatefulWidget {
  const GlowLasso({super.key, required this.points});

  final List<Offset> points;

  @override
  State<GlowLasso> createState() => _GlowLassoState();
}

class _GlowLassoState extends State<GlowLasso>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (widget.points.length < 2) return const SizedBox.expand();

    final colors = <Color>[
      palette.accent,
      palette.primary,
      palette.info,
      palette.primary,
      palette.accent,
    ];

    if (prefersReducedMotion(context)) {
      return CustomPaint(
        size: Size.infinite,
        painter: _GlowLassoPainter(points: widget.points, t: 0, colors: colors,
            glow: palette.accent, pulse: 0.5),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _GlowLassoPainter(
          points: widget.points,
          t: _controller.value,
          colors: colors,
          glow: palette.accent,
          pulse: 0.5 + 0.5 * math.sin(_controller.value * 2 * math.pi),
        ),
      ),
    );
  }
}

class _GlowLassoPainter extends CustomPainter {
  _GlowLassoPainter({
    required this.points,
    required this.t,
    required this.colors,
    required this.glow,
    required this.pulse,
  });

  final List<Offset> points;
  final double t;
  final List<Color> colors;
  final Color glow;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(points.first.dx * size.width, points.first.dy * size.height);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    final bounds = path.getBounds().inflate(36);
    final shader = LinearGradient(
      colors: colors,
      tileMode: TileMode.repeated,
      transform: _SlidingGradient(t),
    ).createShader(bounds);

    Paint stroke(double width, double blur, double alpha, {bool grad = false}) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width;
      if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      if (grad) {
        p.shader = shader;
      } else {
        p.color = glow.withValues(alpha: alpha);
      }
      return p;
    }

    // Wide soft outer halo, a tighter inner halo, then a blurred gradient bloom
    // and finally the crisp gradient stroke on top — layered so it reads as
    // genuinely glowing, not just a coloured line.
    canvas.drawPath(path, stroke(34, 22, 0.10 + 0.14 * pulse));
    canvas.drawPath(path, stroke(18, 10, 0.20 + 0.22 * pulse));
    canvas.drawPath(path, stroke(9, 6, 0, grad: true));
    canvas.drawPath(path, stroke(4.5, 0, 0, grad: true));
  }

  @override
  bool shouldRepaint(_GlowLassoPainter old) =>
      old.t != t || old.points != points || old.pulse != pulse;
}

/// Slides the repeating gradient one width per cycle — a seamless flow.
class _SlidingGradient extends GradientTransform {
  const _SlidingGradient(this.progress);
  final double progress;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * progress, 0, 0);
}
