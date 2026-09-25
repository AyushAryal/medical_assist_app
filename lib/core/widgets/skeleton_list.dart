import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// The shape of the list before the list arrives.
///
/// A centred spinner tells the user *that* the app is working; a skeleton
/// tells them *what* is coming — rows land where rows will be, so the screen
/// doesn't reflow when data appears. The sheen is a single repeating
/// [ShaderMask] over static placeholder boxes: no package dependency, one
/// controller, and every colour is read from the palette rather than the
/// grey the stock shimmer libraries assume.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 6,
    this.padding,
  });

  /// How many placeholder rows to paint. Enough to fill a phone screen by
  /// default; callers with short lists can ask for fewer.
  final int count;

  /// Defaults to the standard list gutter from the metric tokens.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return _Shimmer(
      child: ListView.separated(
        padding: padding ??
            EdgeInsets.fromLTRB(m.spaceLg, m.spaceMd, m.spaceLg, m.space2xl),
        // shrinkWrap so it also renders when given unbounded height (e.g.
        // inside a sliver adapter) instead of laying out to nothing.
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => SizedBox(height: m.spaceSm),
        itemBuilder: (_, _) => const _SkeletonRow(),
      ),
    );
  }
}

/// One placeholder row shaped like a typical list tile: a leading circle and
/// two rounded text bars, on the same muted surface a real row sits on.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final bone = palette.onSurface.withValues(
      alpha: context.isDark ? 0.10 : 0.07,
    );

    return Container(
      padding: EdgeInsets.all(m.spaceLg),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: context.glassOpacity),
        borderRadius: BorderRadius.circular(m.radiusLg),
        border: Border.all(color: palette.outline, width: m.hairline),
      ),
      child: Row(
        children: <Widget>[
          _Bone(color: bone, width: 44, height: 44, circular: true),
          SizedBox(width: m.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Bone(color: bone, width: 160, height: 14),
                SizedBox(height: m.spaceSm),
                _Bone(color: bone, width: 100, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({
    required this.color,
    required this.width,
    required this.height,
    this.circular = false,
  });

  final Color color;
  final double width;
  final double height;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: circular
            ? BorderRadius.circular(height)
            : BorderRadius.circular(m.radiusSm),
      ),
    );
  }
}

/// A moving sheen over the skeleton — dependency-free, one repeating
/// controller, colours derived from the palette so it re-skins with the theme.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});

  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = palette.onSurface.withValues(
      alpha: context.isDark ? 0.10 : 0.06,
    );
    final highlight = palette.onSurface.withValues(
      alpha: context.isDark ? 0.22 : 0.11,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = bounds.width * (_controller.value * 2 - 1);
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[base, highlight, base],
              stops: const <double>[0.25, 0.5, 0.75],
              transform: _SlideGradient(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);

  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}
