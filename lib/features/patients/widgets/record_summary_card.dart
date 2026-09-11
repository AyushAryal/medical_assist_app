import 'package:flutter/material.dart';

import '../../../clinical/flags/clinical_flag.dart';
import '../../../clinical/summary/record_summary.dart';
import '../../../core/design/design.dart';
import '../../assist/assist.dart';

/// The prime-the-chart pre-read: allergies, problems, medications, the latest
/// observations and when the patient was last seen, at a glance — with the
/// gaps called out, not hidden. A clinician walking into a rushed consultation
/// reads this first.
///
/// Every line names its source behind an [InfoDot]; anything the record does
/// not hold reads "Not recorded" in a muted tone, and the count of gaps sits
/// at the top so an absent allergy status cannot pass for a reassuring one.
class RecordSummaryCard extends StatelessWidget {
  const RecordSummaryCard({
    super.key,
    required this.summary,
    this.onHandoff,
    this.onBrief,
    this.onReferral,
    this.onExplain,
  });

  final RecordSummary summary;

  /// Opens the SBAR handoff built from the same record. Null hides the action.
  final VoidCallback? onHandoff;

  /// AI actions over this record. Null hides each (no model installed).
  final VoidCallback? onBrief;
  final VoidCallback? onReferral;
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final gaps = summary.notRecorded.length;
    final items = summary.allItems.toList();

    return SectionCard(
      title: 'Pre-read',
      leading: const Icon(Icons.assignment_ind_outlined, size: 20),
      trailing: SpeakButton(text: summary.plainText),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          StatusPill(
            label: gaps == 0
                ? 'All recorded'
                : '$gaps not recorded',
            tone: gaps == 0 ? PillTone.normal : PillTone.caution,
            icon: gaps == 0 ? Icons.check_circle_outline : Icons.error_outline,
            dense: true,
          ),
          SizedBox(height: m.spaceSm),
          for (var i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0)
              Divider(height: 1, color: palette.outline.withValues(alpha: 0.4)),
            _SummaryRow(item: items[i]),
          ],
          if (onBrief != null ||
              onHandoff != null ||
              onReferral != null ||
              onExplain != null) ...<Widget>[
            SizedBox(height: m.spaceMd),
            // Compact tinted capsules, the way iOS marks a row of secondary
            // actions — four outlined slabs read as four competing forms.
            Wrap(
              spacing: m.spaceSm,
              runSpacing: m.spaceSm,
              children: <Widget>[
                if (onBrief != null)
                  CapsuleAction(
                    onTap: onBrief,
                    icon: Icons.auto_awesome,
                    label: 'Brief me',
                  ),
                if (onExplain != null)
                  CapsuleAction(
                    onTap: onExplain,
                    icon: Icons.help_outline,
                    label: 'Explain',
                  ),
                if (onHandoff != null)
                  CapsuleAction(
                    onTap: onHandoff,
                    icon: Icons.assignment_outlined,
                    label: 'Handoff',
                  ),
                if (onReferral != null)
                  CapsuleAction(
                    onTap: onReferral,
                    icon: Icons.outgoing_mail,
                    label: 'Referral',
                  ),
              ],
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

    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: 5, right: m.spaceSm),
            child: Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: _dotColor(palette), shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.label.toUpperCase(),
                  style: context.texts.labelSmall?.copyWith(
                    color: palette.onSurfaceMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: m.spaceXs / 2),
                Text(
                  item.value,
                  style: context.texts.bodyMedium?.copyWith(
                    color: _valueColor(palette),
                    fontStyle:
                        item.isRecorded ? FontStyle.normal : FontStyle.italic,
                    fontWeight:
                        item.severity == FlagSeverity.critical
                            ? FontWeight.w600
                            : FontWeight.w400,
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
