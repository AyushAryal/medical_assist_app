import 'package:flutter/material.dart';

import '../../theme/theme_scope.dart';
import 'effects_motion.dart';
import 'gradient_box_border.dart';

/// The mark that says a machine produced this.
///
/// Deliberately not a plain icon: generated content has to be distinguishable
/// at a glance from clinician-authored content, and in a record that will be
/// read years later by someone who was not there, that distinction is the
/// difference between evidence and hearsay.
class AiBadge extends StatefulWidget {
  const AiBadge({
    super.key,
    this.label = 'AI generated',
    this.animate = true,
    this.dense = false,
  });

  final String label;

  /// A slow colour drift. On by default: this badge marks the boundary between
  /// what a clinician wrote and what a machine produced, and in a record read
  /// years later by someone who was not there, that is the difference between
  /// evidence and hearsay. It should catch the eye.
  final bool animate;

  /// Smaller, for sitting inline in a list row rather than heading a panel.
  final bool dense;

  @override
  State<AiBadge> createState() => _AiBadgeState();
}

class _AiBadgeState extends State<AiBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // A slow drift, not a scroll. At 4.2s the sheen visibly raced across the
    // pill and, with the colours tiled twice, read as a repeating pattern
    // rather than a single sheen. Much slower reads as a barely-moving gleam,
    // which is what a badge should be — it must never compete with the
    // clinical severity colours.
    duration: const Duration(milliseconds: 11000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(AiBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate) {
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
    final m = context.metrics;
    final reduced = prefersReducedMotion(context);
    final colors = sweepColors(context);

    // One gradient, translated continuously across the pill. An earlier
    // version rotated the colour *list* by an integer index, which ticked a
    // whole step at a time; sliding a repeating shader is what makes it flow.
    //
    // `t` is read inside the builder, not captured outside it. Capturing it in
    // `build` was why these sat frozen: `AnimatedBuilder` re-ran the closure
    // every tick, but the closure held the value from whenever the *parent*
    // last rebuilt, which for a badge on a static panel is never.
    Widget badge(double t) {
      Shader shader(Rect bounds) => LinearGradient(
            colors: <Color>[...colors, ...colors],
            tileMode: TileMode.repeated,
            transform: _SlidingGradient(t),
          ).createShader(bounds);

      final content = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.auto_awesome,
            size: widget.dense ? 10 : 12,
            // Recoloured by the mask below; this only has to be opaque.
            color: Colors.white,
          ),
          SizedBox(width: m.spaceXs / 2),
          Text(
            widget.label,
            style: context.texts.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: widget.dense ? 9.5 : null,
              letterSpacing: 0.2,
            ),
          ),
        ],
      );

      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.dense ? m.spaceXs + 2 : m.spaceSm,
          vertical: m.spaceXs / 2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(m.radiusXs),
          gradient: LinearGradient(
            colors: <Color>[
              for (final colour in <Color>[...colors, ...colors])
                colour.withValues(alpha: context.isDark ? 0.24 : 0.13),
            ],
            tileMode: TileMode.repeated,
            transform: _SlidingGradient(t),
          ),
          border: GradientBoxBorder(
            gradient: LinearGradient(
              colors: <Color>[...colors, ...colors],
              tileMode: TileMode.repeated,
              transform: _SlidingGradient(t),
            ),
            width: 1,
          ),
        ),
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: shader,
          child: content,
        ),
      );
    }

    if (reduced || !widget.animate) return badge(0);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => badge(_controller.value),
    );
  }
}

/// Slides a repeating gradient by a fraction of its own width.
///
/// The colours are supplied twice and tiled, so translating by exactly one
/// list-width per cycle returns to the starting arrangement — the loop has no
/// seam, which is what separates a drifting sheen from a visible restart.
class _SlidingGradient extends GradientTransform {
  const _SlidingGradient(this.progress);

  /// 0–1 through one full cycle.
  final double progress;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(-bounds.width * progress, 0, 0);
}
