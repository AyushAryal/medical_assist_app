import 'dart:math' as math;

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

/// Backs the moving page with an opaque glass fill *while it travels*, so the
/// outgoing page is occluded rather than showing straight through, then clears
/// to nothing when it settles and the ambient wash returns.
///
/// A live `BackdropFilter` blur is the truer "refraction", but re-rasterising a
/// blur every frame under an interactive edge-swipe stutters the drag — so this
/// uses a cheap colour fill, which the finger-drag can keep up with.
class _LiquidGlass extends StatelessWidget {
  const _LiquidGlass({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).canvasColor;

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // Zero at both ends (off-screen and settled), peaking mid-travel.
        final occlude = math.sin(animation.value.clamp(0.0, 1.0) * math.pi) * 0.9;
        if (occlude < 0.02) return child!;
        return ColoredBox(
          color: fill.withValues(alpha: occlude),
          child: child,
        );
      },
    );
  }
}
