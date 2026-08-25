/// Motion for the moments the app is working something out.
///
/// This is a deliberate, bounded exception to the system's "minimal gradients"
/// rule, and it is worth being explicit about why it earns one. Everywhere
/// else, a gradient would be decoration. Here it is a *signal*: it marks the
/// difference between text the clinician wrote and text a machine produced, and
/// between a screen that is idle and one that is thinking. Those are exactly
/// the distinctions this app must never let blur.
///
/// The rules that keep it from spreading:
///
/// * **Only for generated content and in-progress inference.** Never for a
///   save, a load, or anything a clinician did themselves.
/// * **Colour comes from the palette.** No new hues; the sweep is built from
///   `accent`, `primary` and `info`, so it re-skins with everything else.
/// * **It stops.** Every animation here is bounded by an `active` flag and
///   disposes its controller. Nothing loops forever behind a finished result.
/// * **It respects reduced motion.** When the platform asks for less motion
///   the effect degrades to a static tint rather than being merely slowed —
///   for a vestibular-sensitive user a slow sweep is worse than none.
///
/// Documented as a known deviation in `DesignSystem.md` §6.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// How much motion the viewer has asked for.
bool _prefersReducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The palette hues a sweep is built from, in order.
List<Color> _sweepColors(BuildContext context) {
  final palette = context.palette;
  // Six stops rather than three: a sweep with too few reads as two blocks
  // rotating, and the point is a continuous shimmer. The severity hues
  // (`caution`, `critical`) are deliberately absent — they mean a clinical
  // state, and borrowing them here for decoration would blunt the one
  // signal in this app that must never be ambiguous.
  return <Color>[
    palette.accent,
    palette.primary,
    palette.info,
    palette.accent,
    palette.primary,
    palette.accent,
  ];
}

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
    final reduced = _prefersReducedMotion(context);

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
                    : _sweepColors(context),
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
    if (!widget.active || _prefersReducedMotion(context)) return widget.child;

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

/// Placeholder lines that shimmer while text is being produced.
///
/// Shown instead of a spinner because it previews the *shape* of what is
/// coming. A spinner says "wait"; this says "paragraphs of text are on their
/// way", which is the honest signal when transcription takes longer than the
/// recording did.
class AiTextPlaceholder extends StatelessWidget {
  const AiTextPlaceholder({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return AiShimmer(
      active: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < lines; i++)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceSm),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                // A ragged right edge reads as prose; equal bars read as a
                // loading skeleton for a table.
                widthFactor: i == lines - 1 ? 0.55 : (i.isEven ? 0.95 : 0.8),
                child: Container(
                  height: 11,
                  decoration: BoxDecoration(
                    color: palette.onSurfaceMuted.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(m.radiusXs),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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
    // Slow enough to read as a sheen rather than a flash. A badge that pulses
    // urgently competes with the clinical severity colours, which is exactly
    // what it must not do.
    duration: const Duration(milliseconds: 4200),
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
    final reduced = _prefersReducedMotion(context);
    final colors = _sweepColors(context);

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
    final show = widget.active && !_prefersReducedMotion(context);

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
                        colors: _sweepColors(context),
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

    if (!widget.active || _prefersReducedMotion(context)) {
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


/// A border painted with a gradient rather than a single colour.
///
/// Flutter's [Border] takes one colour per side, so a multi-hue outline needs
/// its own painter. Kept here beside the badge that needs it rather than added
/// to the general design layer — a gradient outline is only ever correct for
/// marking generated content.
class GradientBoxBorder extends BoxBorder {
  const GradientBoxBorder({required this.gradient, this.width = 1});

  final Gradient gradient;
  final double width;

  @override
  BorderSide get bottom => BorderSide.none;

  @override
  BorderSide get top => BorderSide.none;

  @override
  bool get isUniform => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    final paint = Paint()
      ..strokeWidth = width
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke;

    if (borderRadius != null) {
      canvas.drawRRect(borderRadius.toRRect(rect).deflate(width / 2), paint);
    } else if (shape == BoxShape.circle) {
      canvas.drawCircle(rect.center, rect.shortestSide / 2 - width / 2, paint);
    } else {
      canvas.drawRect(rect.deflate(width / 2), paint);
    }
  }

  @override
  ShapeBorder scale(double t) =>
      GradientBoxBorder(gradient: gradient, width: width * t);
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
