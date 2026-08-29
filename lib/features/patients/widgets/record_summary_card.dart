import 'package:flutter/material.dart';

import '../../../clinical/flags/clinical_flag.dart';
import '../../../clinical/summary/record_summary.dart';
import '../../../core/design/design.dart';

/// The prime-the-chart pre-read: allergies, problems, medications, the latest
/// observations and when the patient was last seen, at a glance — with the
/// gaps called out, not hidden. A clinician walking into a rushed consultation
/// reads this first.
///
/// Every line names its source behind an [InfoDot]; anything the record does
/// not hold reads "Not recorded" in a muted tone, and the count of gaps sits
/// in the header so an absent allergy status cannot pass for a reassuring one.
class RecordSummaryCard extends StatelessWidget {
  const RecordSummaryCard({
    super.key,
    required this.summary,
    this.onHandoff,
    this.onBrief,
  });

  final RecordSummary summary;

  /// Opens the SBAR handoff built from the same record. Null hides the action.
  final VoidCallback? onHandoff;

  /// Generates an AI spoken brief of this summary. Null hides the action (no
  /// model installed).
  final VoidCallback? onBrief;

  @override
  Widget build(BuildContext context) {
    final gaps = summary.notRecorded.length;
    return SectionCard(
      title: 'Pre-read',
      subtitle: gaps == 0
          ? 'Everything here is on the record.'
          : '$gaps ${gaps == 1 ? 'thing' : 'things'} not recorded.',
      trailing: onHandoff == null
          ? null
          : TextButton.icon(
              onPressed: onHandoff,
              icon: const Icon(Icons.assignment_outlined, size: 18),
              label: const Text('Handoff'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final section in summary.sections)
            for (final item in section.items) _SummaryRow(item: item),
          if (onBrief != null) ...<Widget>[
            SizedBox(height: context.metrics.spaceSm),
            OutlinedButton.icon(
              onPressed: onBrief,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Brief me'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.item});

  final SummaryItem item;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final dot = _dotColor(palette);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: m.spaceXs, right: m.spaceSm),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item.label, style: context.texts.labelMedium),
                Text(
                  item.value,
                  style: context.texts.bodySmall?.copyWith(
                    color: _valueColor(palette),
                    fontStyle:
                        item.isRecorded ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          InfoDot.text(
            title: item.label,
            summary: item.isRecorded
                ? 'Read directly from the record.'
                : 'Not on the record — shown so the gap is not mistaken for a '
                    'reassuring answer.',
            source: item.source,
          ),
        ],
      ),
    );
  }

  Color _dotColor(ClinicalPalette p) => switch (item.severity) {
        FlagSeverity.critical => p.critical,
        FlagSeverity.caution => p.caution,
        FlagSeverity.info => p.info,
        // Neutral: a faint mark for what is on record, a muted one for a gap.
        null => item.isRecorded ? p.normal : p.onSurfaceMuted,
      };

  Color _valueColor(ClinicalPalette p) {
    if (!item.isRecorded) return p.onSurfaceMuted;
    return switch (item.severity) {
      FlagSeverity.critical => p.critical,
      _ => p.onSurface,
    };
  }
}
