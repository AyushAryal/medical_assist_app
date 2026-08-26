import 'package:flutter/material.dart';

import '../widgets/glass.dart';

/// Material's "fade through": the outgoing page fades out via
/// `secondaryAnimation`, then the incoming page fades in via `animation`, so
/// the two are never both fully opaque at once. Shared by go_router's
/// `_fadeThrough` (app_router.dart) and [FadeThroughRoute].
Widget buildFadeThroughTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final entrance = CurvedAnimation(
    parent: animation,
    curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
  );
  final exit = CurvedAnimation(
    parent: secondaryAnimation,
    curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
  );
  return FadeTransition(
    opacity: Tween<double>(begin: 1, end: 0).animate(exit),
    child: FadeTransition(opacity: entrance, child: child),
  );
}

/// Gives a full-screen page its own opaque copy of the ambient background
/// instead of relying on the transparent `Scaffold` to reveal the one copy
/// mounted at the app root. [AmbientBackground] is deterministic, so nesting
/// it costs nothing — but it means two pages on screen during a transition
/// always share the same base layer, whatever's animating them.
Widget wrapWithAmbient(Widget child) => AmbientBackground(child: child);

/// A plain [Navigator.push] route carrying the same fade-through transition
/// as go_router's full-screen routes.
///
/// Use instead of [MaterialPageRoute] for a full-screen push outside
/// go_router (e.g. the draft review screen pushed from the note editor).
/// `MaterialPageRoute`'s platform-default transition is what this avoids —
/// on iOS especially, the default slide keeps both pages visible at once.
class FadeThroughRoute<T> extends PageRouteBuilder<T> {
  FadeThroughRoute({required WidgetBuilder builder, super.fullscreenDialog})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            wrapWithAmbient(builder(context)),
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: buildFadeThroughTransition,
      );
}
