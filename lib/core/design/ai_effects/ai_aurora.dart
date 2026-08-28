import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/theme_scope.dart';
import 'effects_motion.dart';

/// A slow drifting field of colour, for the background of an AI surface.
///
/// Three soft blobs on independent orbits. Kept very low-contrast: it has to
/// register as "this panel is different" at a glance and then get out of the
/// way, because clinical text is going to be read on top of it.
class AiAuroraBackground extends StatefulWidget {
  const AiAuroraBackground({
    super.key,
    required this.child,
    this.active = true,
    this.intensity = 1.0,
  });

  final Widget child;
  final bool active;

  /// Scales the opacity. Below about 0.6 it is barely visible; above 1.2 it
  /// starts to fight the text.
  final double intensity;

  @override
  State<AiAuroraBackground> createState() => _AiAuroraBackgroundState();
}

class _AiAuroraBackgroundState extends State<AiAuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(AiAuroraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final show = widget.active && !prefersReducedMotion(context);

    // Same shape either way — see the note in [AiGlowBorder]. A layout that
    // changes depth when an effect turns on rebuilds everything beneath it.
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: show
                    ? _AuroraPainter(
                        progress: _controller.value,
                        colors: sweepColors(context),
                        intensity:
                            widget.intensity * (context.isDark ? 0.26 : 0.18),
                      )
                    : null,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.progress,
    required this.colors,
    required this.intensity,
  });

  final double progress;
  final List<Color> colors;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final turn = progress * 2 * math.pi;
    // Coprime-ish speeds, so the blobs never settle into a repeating
    // arrangement the eye can lock onto.
    const orbits = <({double speed, double radius, double phase})>[
      (speed: 1.0, radius: 0.42, phase: 0),
      (speed: -0.7, radius: 0.34, phase: 2.1),
      (speed: 1.3, radius: 0.38, phase: 4.2),
    ];

    for (var i = 0; i < orbits.length; i++) {
      final orbit = orbits[i];
      final angle = turn * orbit.speed + orbit.phase;
      final centre = Offset(
        size.width * (0.5 + math.cos(angle) * 0.28),
        size.height * (0.5 + math.sin(angle * 1.4) * 0.32),
      );
      final radius = size.shortestSide * orbit.radius;

      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              colors[i % colors.length].withValues(alpha: intensity),
              colors[i % colors.length].withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(center: centre, radius: radius),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.progress != progress || old.intensity != intensity;
}
