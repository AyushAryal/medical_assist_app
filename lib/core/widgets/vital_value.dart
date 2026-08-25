import 'package:flutter/material.dart';

import '../../clinical/explanations.dart';
import '../../clinical/vital_reference.dart';
import '../theme/theme_config.dart';
import '../theme/theme_scope.dart';
import 'info_dot.dart';

/// A single observation rendered with its reference flag.
///
/// Colour is never the only signal — an `H`/`L` marker carries the same
/// information, so the reading stays correct for a colour-blind user and in
/// direct sunlight on a ward.
class VitalValue extends StatelessWidget {
  const VitalValue({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.flag = VitalFlag.unknown,
    this.reference,
    this.delta,
    this.compact = false,
    this.explanation,
  });

  final String label;
  final String value;
  final String? unit;
  final VitalFlag flag;
  final String? reference;

  /// Change since the previous reading, pre-formatted (e.g. `+8`). Trend is
  /// often more informative than the absolute number.
  final String? delta;
  final bool compact;

  /// Why this reading carries the flag it carries. An `H` beside a number is
  /// an assertion the app is making on the clinician's behalf, and it should
  /// always be possible to ask which band produced it — paediatric ranges in
  /// particular are not something anyone holds in their head.
  final MetricExplanation? explanation;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final tone = _tone(palette, flag);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label.toUpperCase(),
              style: context.texts.labelSmall?.copyWith(letterSpacing: 0.5),
            ),
            if (explanation case final explanation?)
              InfoDot(
                explanation: explanation,
                semanticLabel: 'Why $label reads as '
                    '${flag == VitalFlag.normal ? 'normal' : flag.label}',
              ),
          ],
        ),
        SizedBox(height: m.spaceXs / 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              value,
              style: TextStyle(
                fontSize: compact
                    ? context.typography.bodySize + 2
                    : context.typography.dataSize + 3,
                fontWeight: FontWeight.w700,
                color: tone,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            if (unit != null) ...<Widget>[
              const SizedBox(width: 3),
              Text(
                unit!,
                style: context.texts.labelSmall?.copyWith(color: tone),
              ),
            ],
            if (flag.isAbnormal) ...<Widget>[
              SizedBox(width: m.spaceXs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  flag.shortLabel,
                  style: context.texts.labelSmall?.copyWith(
                    color: palette.surface,
                    fontWeight: FontWeight.w800,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (delta != null || (reference != null && !compact))
          Padding(
            padding: EdgeInsets.only(top: m.spaceXs / 2),
            child: Text(
              <String?>[delta, reference].where((s) => s != null).join('  ·  '),
              style: context.texts.labelSmall,
            ),
          ),
      ],
    );
  }

  static Color _tone(ClinicalPalette palette, VitalFlag flag) => switch (flag) {
        VitalFlag.criticalLow || VitalFlag.criticalHigh => palette.critical,
        VitalFlag.low || VitalFlag.high => palette.caution,
        VitalFlag.normal => palette.onSurface,
        VitalFlag.unknown => palette.onSurfaceMuted,
      };
}
