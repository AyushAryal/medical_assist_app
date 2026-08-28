import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/theme_scope.dart';
import 'effects_motion.dart';

/// A slowly rotating gradient outline, for a surface that is thinking.
///
/// The border rather than the fill: a filled shimmer over a panel makes the
/// text under it hard to read at exactly the moment someone is trying to read
/// it, and a clinical draft has to stay legible while it arrives.
class AiGlowBorder extends StatefulWidget {
  const AiGlowBorder({
    super.key,
    required this.child,
    required this.active,
    this.borderRadius,
    this.strokeWidth = 1.6,
  });

  final Widget child;

  /// Animates only while true. Turning it off leaves the child untouched, with
  /// no residual border, so a finished result does not keep pulsing.
  final bool active;

  final BorderRadius? borderRadius;
  final double strokeWidth;

  @override
  State<AiGlowBorder> createState() => _AiGlowBorderState();
}

class _AiGlowBorderState extends State<AiGlowBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(AiGlowBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ??
        BorderRadius.circular(context.metrics.radiusMd);
    final reduced = prefersReducedMotion(context);

    // The widget tree keeps the same shape whether or not the border is
    // active, and that is a correctness requirement rather than tidiness.
    // Returning `child` directly when inactive changes the depth of everything
    // below on every toggle, which rebuilds it — and a rebuilt `TextField`
    // has its composing region re-applied by the platform keyboard, so
    // deleted characters reappear as the user types. Only the painter is
    // switched.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        foregroundPainter: widget.active
            ? _GlowBorderPainter(
                progress: reduced ? 0 : _controller.value,
                colors: reduced
                    ? <Color>[context.palette.accent, context.palette.accent]
                    : sweepColors(context),
                radius: radius,
                strokeWidth: widget.strokeWidth,
              )
            : null,
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _GlowBorderPainter extends CustomPainter {
  _GlowBorderPainter({
    required this.progress,
    required this.colors,
    required this.radius,
    required this.strokeWidth,
  });

  final double progress;
  final List<Color> colors;
  final BorderRadius radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Inset by half the stroke so the ring sits fully inside the bounds rather
    // than being clipped in half by the parent.
    final outline = radius.toRRect(rect).deflate(strokeWidth / 2);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        colors: colors,
        transform: GradientRotation(progress * 2 * math.pi),
      ).createShader(rect);

    canvas.drawRRect(outline, paint);
  }

  @override
  bool shouldRepaint(_GlowBorderPainter old) =>
      old.progress != progress ||
      old.strokeWidth != strokeWidth ||
      old.colors != colors;
}
