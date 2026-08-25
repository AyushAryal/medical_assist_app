import 'package:flutter/material.dart';

import '../theme/theme_config.dart';
import '../theme/theme_scope.dart';

/// Severity of a pill, mapped onto the clinical semantic colours rather than
/// onto arbitrary UI colours.
enum PillTone { neutral, info, normal, caution, critical }

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = PillTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final (background, foreground) = _colors(palette);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? m.spaceXs + 2 : m.spaceSm,
        vertical: dense ? 1 : m.spaceXs - 1,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(m.radiusSm),
        border: Border.all(color: foreground.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 12 : 14, color: foreground),
            SizedBox(width: m.spaceXs),
          ],
          Text(
            label,
            style: (dense ? context.texts.labelSmall : context.texts.labelMedium)
                ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  (Color, Color) _colors(ClinicalPalette p) => switch (tone) {
        PillTone.neutral => (p.surfaceMuted, p.onSurfaceMuted),
        PillTone.info => (p.infoSubtle, p.info),
        PillTone.normal => (p.normalSubtle, p.normal),
        PillTone.caution => (p.cautionSubtle, p.caution),
        PillTone.critical => (p.criticalSubtle, p.critical),
      };
}
