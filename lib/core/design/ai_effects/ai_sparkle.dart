import 'package:flutter/material.dart';

import '../../theme/theme_scope.dart';
import 'effects_motion.dart';

/// A gently breathing sparkle, for a control that starts an AI action.
class AiSparkleIcon extends StatefulWidget {
  const AiSparkleIcon({super.key, this.size = 20, this.active = true});

  final double size;
  final bool active;

  @override
  State<AiSparkleIcon> createState() => _AiSparkleIconState();
}

class _AiSparkleIconState extends State<AiSparkleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AiSparkleIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
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
    final palette = context.palette;

    if (!widget.active || prefersReducedMotion(context)) {
      return Icon(Icons.auto_awesome, size: widget.size, color: palette.accent);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.scale(
          scale: 0.92 + t * 0.16,
          child: Icon(
            Icons.auto_awesome,
            size: widget.size,
            color: Color.lerp(palette.accent, palette.primary, t),
          ),
        );
      },
    );
  }
}
