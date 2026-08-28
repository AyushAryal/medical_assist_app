import 'package:flutter/material.dart';

import '../../theme/theme_scope.dart';
import 'effects_motion.dart';

/// A light sweeping across content, for text that is being produced.
///
/// Applied to placeholder bars while waiting, and to freshly arrived text for
/// one pass so the eye is drawn to what changed.
class AiShimmer extends StatefulWidget {
  const AiShimmer({
    super.key,
    required this.child,
    required this.active,
    this.repeat = true,
  });

  final Widget child;
  final bool active;

  /// False sweeps once and stops — the "here is your result" gesture, rather
  /// than the "still working" one.
  final bool repeat;

  @override
  State<AiShimmer> createState() => _AiShimmerState();
}

class _AiShimmerState extends State<AiShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    if (!widget.active) return;
    if (widget.repeat) {
      _controller.repeat();
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(AiShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _start();
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
    if (!widget.active || prefersReducedMotion(context)) return widget.child;

    final palette = context.palette;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            // A narrow highlight travelling left to right. It starts and ends
            // fully off-screen so there is no visible pop at the loop point.
            final travel = _controller.value * 2 - 0.5;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                palette.accent.withValues(alpha: 0),
                palette.accent.withValues(alpha: 0.55),
                palette.accent.withValues(alpha: 0),
              ],
              stops: <double>[
                (travel - 0.18).clamp(0.0, 1.0),
                travel.clamp(0.0, 1.0),
                (travel + 0.18).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
