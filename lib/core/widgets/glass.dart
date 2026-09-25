import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// A translucent, blurred panel — the app's primary content surface.
///
/// The blur is the point. A flat semi-transparent rectangle just looks washed
/// out; sampling and blurring what sits behind it is what makes it read as a
/// material with depth, and it lets the interface carry a sense of layering
/// without gradients or heavy drop shadows.
///
/// Blur is expensive, so this is used for panels and chrome — never per row in
/// a long list.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.radius,
    this.opacity,
    this.blur,
    this.border = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? radius;
  final double? opacity;
  final double? blur;
  final bool border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final corner = radius ?? m.radiusMd;

    return ClipRRect(
      borderRadius: BorderRadius.circular(corner),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blur ?? m.glassBlur,
          sigmaY: blur ?? m.glassBlur,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.glassTint
                .withValues(alpha: opacity ?? context.glassOpacity),
            borderRadius: BorderRadius.circular(corner),
            border: border
                ? Border.all(
                    // A hairline of the *foreground* colour at very low alpha
                    // catches the light along the panel edge, the way a real
                    // pane of frosted glass does.
                    color: palette.onSurface.withValues(
                      alpha: context.isDark ? 0.09 : 0.05,
                    ),
                    width: m.hairline,
                  )
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: padding ?? EdgeInsets.all(m.spaceLg),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Blurred chrome for bars that content scrolls beneath.
class GlassChrome extends StatelessWidget {
  const GlassChrome({
    super.key,
    required this.child,
    this.topBorder = false,
    this.bottomBorder = false,
  });

  final Widget child;
  final bool topBorder;
  final bool bottomBorder;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: m.chromeBlur, sigmaY: m.chromeBlur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: context.chromeOpacity),
            border: Border(
              top: topBorder
                  ? BorderSide(color: palette.outline, width: m.hairline)
                  : BorderSide.none,
              bottom: bottomBorder
                  ? BorderSide(color: palette.outline, width: m.hairline)
                  : BorderSide.none,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A blurred strip covering the status bar.
///
/// Screens that scroll edge-to-edge without an AppBar would otherwise run
/// content straight under the system clock and battery icons, which looks
/// broken and can make a patient name genuinely unreadable. This gives that
/// strip the same material treatment as the rest of the chrome.
class StatusBarScrim extends StatelessWidget {
  const StatusBarScrim({super.key});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.paddingOf(context).top;
    if (height == 0) return const SizedBox.shrink();

    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: const GlassChrome(child: SizedBox.expand()),
      ),
    );
  }
}

/// The OptERP family wash painted behind the whole app — a soft coral → violet
/// → blue sweep so OptDAI reads as part of the suite rather than a flat violet
/// app. Clinical content sits on opaque glass panels, so the wash colours the
/// space *between* panels and behind chrome without tinting records themselves.
///
/// Three brand blobs (warm top-left, violet mid, cool bottom-right) mirror the
/// family gradient direction; kept translucent so it stays calm and legible.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final strength = context.isDark ? 0.34 : 0.22;

    return DecoratedBox(
      decoration: BoxDecoration(color: palette.surfaceMuted),
      child: Stack(
        children: <Widget>[
          // Coral — warm anchor, top-left (gradient origin).
          Positioned(
            top: -170,
            left: -130,
            child: _Blob(color: palette.ambientOne, alpha: strength, size: 560),
          ),
          // Violet — the brand core, drifting through the middle.
          Positioned(
            top: 240,
            left: -60,
            child: _Blob(
              color: palette.heroSurface,
              alpha: strength * 0.7,
              size: 520,
            ),
          ),
          // Blue — cool end, bottom-right (gradient terminus).
          Positioned(
            bottom: -200,
            right: -160,
            child: _Blob(
              color: palette.ambientTwo,
              alpha: strength * 0.9,
              size: 560,
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.alpha, required this.size});

  final Color color;
  final double alpha;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
