import 'package:flutter/material.dart';

import '../../theme/theme_scope.dart';
import 'ai_glow_border.dart';

/// The mark that says a machine produced this.
///
/// Deliberately not a plain icon: generated content has to be distinguishable
/// at a glance from clinician-authored content, and in a record that will be
/// read years later by someone who was not there, that distinction is the
/// difference between evidence and hearsay.
///
/// Wears the same dress as every other AI affordance — a stadium pill on the
/// surface colour with the slowly rotating sweep border — so the mark on
/// generated *content* and the buttons that *produce* it read as one family.
class AiBadge extends StatelessWidget {
  const AiBadge({
    super.key,
    this.label = 'AI generated',
    this.animate = true,
    this.dense = false,
  });

  final String label;

  /// The rotating sweep. On by default: this badge marks the boundary between
  /// what a clinician wrote and what a machine produced, and it should catch
  /// the eye — while never competing with the clinical severity colours.
  final bool animate;

  /// Smaller, for sitting inline in a list row rather than heading a panel.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final radius = BorderRadius.circular(m.radiusLg * 2);

    return AiGlowBorder(
      active: animate,
      borderRadius: radius,
      strokeWidth: 1,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? m.spaceSm : m.spaceSm + 2,
          vertical: dense ? m.spaceXs / 2 : m.spaceXs,
        ),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: radius,
          // The glow border only paints while animating; a badge with the
          // motion switched off still needs an edge to be a badge.
          border: animate
              ? null
              : Border.all(
                  color: palette.accent.withValues(alpha: 0.6),
                  width: 1,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.auto_awesome,
              size: dense ? 10 : 12,
              color: palette.accent,
            ),
            SizedBox(width: m.spaceXs / 2 + 2),
            Text(
              label,
              style: context.texts.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: dense ? 9.5 : null,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
