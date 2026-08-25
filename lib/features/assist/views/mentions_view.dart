import 'package:flutter/material.dart';

import '../../../ai/presentation.dart';
import '../../../core/design/design.dart';
import '../../../core/utils/formatters.dart';
import 'support.dart';

/// Records found in prose rather than by a filter.
///
/// The excerpt is the whole point: it is what lets "father takes warfarin" be
/// dismissed without opening the chart, and it is why a fuzzy secondary list
/// can be offered at all rather than being too noisy to show.
class MentionsAnswerView extends StatelessWidget {
  const MentionsAnswerView({
    super.key,
    required this.result,
    required this.compact,
    required this.rowLimit,
    this.onExpand,
  });

  final MentionsPresentation result;
  final bool compact;
  final int rowLimit;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final shown = result.mentions.take(rowLimit).toList();

    return SectionCard(
      title: 'Not an exact match',
      subtitle: 'Found in something someone wrote',
      leading: const AiSparkleIcon(size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final mention in shown)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceSm),
              child: InkWell(
                onTap: () => openChart(mention.patient.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        PatientAvatar(
                          initials: mention.patient.initials,
                          seed: mention.patient.id,
                          radius: 13,
                        ),
                        SizedBox(width: m.spaceSm),
                        Expanded(
                          child: Text(
                            mention.patient.displayName,
                            style: context.texts.bodyMedium,
                          ),
                        ),
                        Text(
                          '${mention.field} · ${Fmt.date(mention.at)}',
                          style: context.texts.labelSmall,
                        ),
                      ],
                    ),
                    SizedBox(height: m.spaceXs),
                    // The sentence, always. It is what lets an irrelevant hit
                    // be dismissed without opening the chart.
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(m.spaceSm),
                      decoration: BoxDecoration(
                        color: palette.surfaceMuted,
                        borderRadius: BorderRadius.circular(m.radiusXs),
                      ),
                      child: Text(
                        mention.excerpt,
                        maxLines: compact ? 2 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Text(
            'Prose says what was true that day, not what is true now.',
            style: context.texts.labelSmall,
          ),
          if (result.mentions.length > shown.length)
            SeeAllFooter(
              label: '${result.mentions.length} in total',
              onExpand: onExpand,
            ),
        ],
      ),
    );
  }
}
