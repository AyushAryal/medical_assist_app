import 'package:flutter/material.dart';

import '../../theme/theme_scope.dart';

/// How much motion the viewer has asked for.
bool prefersReducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The palette hues a sweep is built from, in order.
List<Color> sweepColors(BuildContext context) {
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
