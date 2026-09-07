import 'package:flutter/material.dart';

import '../../../clinical/news2.dart';
import '../../../core/design/design.dart';

/// Live NEWS2 as the observations are typed.
///
/// Showing the score during entry, rather than after saving, means a
/// deteriorating patient is flagged while the clinician is still at the
/// bedside.
class News2Preview extends StatelessWidget {
  const News2Preview({super.key, required this.input, required this.ageYears});

  final News2Input input;
  final int? ageYears;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    final reason = News2Calculator.unavailableReason(
      ageYears: ageYears,
      isPregnant: false,
      input: input,
    );

    if (reason != null) {
      final message = switch (reason) {
        News2Unavailable.ageOutOfScope =>
          'NEWS2 applies to patients aged 16 and over.',
        News2Unavailable.pregnancy => 'NEWS2 is not validated in pregnancy.',
        News2Unavailable.incompleteObservations =>
          'NEWS2 needs all seven observations — '
              '${News2Calculator.missingParameters(input).length} still missing.',
      };
      return Container(
        padding: EdgeInsets.all(m.spaceMd),
        decoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(m.radiusSm),
          border: Border.all(color: palette.outline),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline, size: 16, color: palette.onSurfaceMuted),
            SizedBox(width: m.spaceSm),
            Expanded(child: Text(message, style: context.texts.bodySmall)),
          ],
        ),
      );
    }

    final result = News2Calculator.score(
      ageYears: ageYears,
      isPregnant: false,
      input: input,
    )!;

    final tone = switch (result.risk) {
      News2Risk.high => PillTone.critical,
      News2Risk.medium || News2Risk.lowMedium => PillTone.caution,
      News2Risk.low => PillTone.normal,
    };

    return Container(
      padding: EdgeInsets.all(m.spaceMd),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(m.radiusSm),
        border: Border.all(color: palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('NEWS2', style: context.texts.titleSmall),
              SizedBox(width: m.spaceSm),
              StatusPill(
                label: '${result.total} · ${result.risk.label}',
                tone: tone,
              ),
              const Spacer(),
              if (result.hasSingleParameterThree)
                const StatusPill(
                  label: 'Single param = 3',
                  tone: PillTone.caution,
                  dense: true,
                ),
            ],
          ),
          SizedBox(height: m.spaceSm),
          Text(result.risk.response, style: context.texts.bodySmall),
          SizedBox(height: m.spaceSm),
          Wrap(
            spacing: m.spaceSm,
            runSpacing: m.spaceXs,
            children: result.parameterScores.entries
                .where((entry) => entry.value > 0)
                .map(
                  (entry) => StatusPill(
                    label: '${entry.key} +${entry.value}',
                    tone: entry.value >= 3
                        ? PillTone.critical
                        : PillTone.caution,
                    dense: true,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
