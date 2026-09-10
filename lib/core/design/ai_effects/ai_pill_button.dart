import 'package:flutter/material.dart';

import '../../theme/theme_scope.dart';
import 'ai_glow_border.dart';
import 'ai_sparkle.dart';

/// A compact pill that starts an AI action — sparkle, gradient outline, and a
/// short label.
///
/// The buttons that *produce* generated content should wear the same mark the
/// content itself wears, so the association is learned before the first tap.
/// Uses the shared sweep hues; the severity colours stay reserved for
/// clinical state.
class AiPillButton extends StatelessWidget {
  const AiPillButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final radius = BorderRadius.circular(m.radiusLg * 2);

    // The same rotating sweep the assistant bubble wears. A static gradient
    // stroked around a small pill reads as fixed colour segments — a striped
    // rope — where the point is one gleam travelling the outline.
    return AiGlowBorder(
      active: true,
      borderRadius: radius,
      strokeWidth: 1.4,
      child: Material(
        color: palette.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: m.spaceMd,
              vertical: m.spaceSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const AiSparkleIcon(size: 16),
                SizedBox(width: m.spaceXs + 2),
                Text(
                  label,
                  style: context.texts.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
