import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The iOS page slide, but the moving page is liquid glass.
///
/// Every screen is a transparent `Scaffold` over one shared ambient wash, so
/// the translucent panels can sample a common ground. With the default slide
/// the incoming page is see-through and the outgoing page shows straight
/// through it — two crisp layers at once, which reads as a glitch. Here the
/// incoming page refracts what is behind it (a strong, high-transparency
/// frost that swells while it travels and clears as it settles), so a screen
/// change reads as one glass surface sliding over another.
///
/// It delegates the slide itself to [CupertinoRouteTransitionMixin], which is
/// what carries the native interactive edge-swipe-back gesture, and only wraps
/// that in the refraction — so the glass never costs the back-swipe.
class GlassPageTransitionsBuilder extends PageTransitionsBuilder {
  const GlassPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slide = CupertinoRouteTransitionMixin.buildPageTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
    return _LiquidGlass(animation: animation, child: slide);
  }
}

/// Refracts the backdrop through the moving page while it is in motion.
class _LiquidGlass extends StatelessWidget {
  const _LiquidGlass({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value.clamp(0.0, 1.0);
        // Zero at both ends (off-screen and settled), peaking mid-travel. A
        // heavy sigma reads as high refraction; the fill stays almost fully
        // transparent so it is glass, not fog.
        final wave = math.sin(t * math.pi);
        final blur = wave * 22;
        if (blur < 0.5) return child!;
        return ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: wave * 0.04),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
