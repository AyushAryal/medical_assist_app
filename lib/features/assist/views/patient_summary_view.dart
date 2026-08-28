import 'package:flutter/material.dart';

import '../../../ai/presentation.dart';
import '../../../core/design/design.dart';

/// Renders a [PatientSummaryPresentation] — one patient gathered from the
/// record.
///
/// The section order follows the question: a plain summary leads with the
/// standing record (problems, medications), a "how are they progressing"
/// reading leads with what is moving (trends, latest observations). Nothing
/// here is styled as generated, because none of it is — it is the chart, read
/// back.
class PatientSummaryAnswerView extends StatelessWidget {
  const PatientSummaryAnswerView({super.key, required this.result});

  final PatientSummaryPresentation result;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    final problems = _ListCard(
      title: 'Active problems',
      icon: Icons.assignment_outlined,
      lines: result.problems,
      emptyLabel: 'No active problems recorded.',
    );
    final medications = _ListCard(
      title: 'Current medications',
      icon: Icons.medication_outlined,
      lines: result.medications,
      emptyLabel: 'No current medications recorded.',
    );
    final observations = _ObservationsCard(result: result);
    final trends = result.trends.isEmpty
        ? null
        : _ListCard(
            title: 'Moving the wrong way',
            icon: Icons.trending_up,
            lines: result.trends,
            tone: context.palette.caution,
          );
    final visits = _VisitsCard(visits: result.visits);
    final upcoming = result.upcoming.isEmpty
        ? null
        : _ListCard(
            title: 'Upcoming',
            icon: Icons.event_outlined,
            lines: result.upcoming,
          );

    final ordered = result.progression
        ? <Widget?>[trends, observations, visits, problems, medications, upcoming]
        : <Widget?>[problems, medications, observations, trends, visits, upcoming];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(result.identityLine, style: context.texts.bodySmall),
        if (result.allergyLine case final allergy?) ...<Widget>[
          SizedBox(height: m.spaceSm),
          _AllergyLine(text: allergy),
        ],
        for (final section in ordered)
          if (section != null) ...<Widget>[
            SizedBox(height: m.spaceMd),
            section,
          ],
      ],
    );
  }
}

class _AllergyLine extends StatelessWidget {
  const _AllergyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isWarning = text.startsWith('Allergies:');
    return Callout(
      title: text,
      icon: isWarning ? Icons.warning_amber_rounded : Icons.check_circle_outline,
      tone: isWarning ? palette.critical : palette.normal,
      child: const SizedBox.shrink(),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.icon,
    required this.lines,
    this.emptyLabel,
    this.tone,
  });

  final String title;
  final IconData icon;
  final List<String> lines;
  final String? emptyLabel;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    if (lines.isEmpty && emptyLabel == null) return const SizedBox.shrink();

    return SectionCard(
      title: title,
      leading: Icon(icon, size: 20, color: tone ?? palette.onSurfaceMuted),
      child: lines.isEmpty
          ? Text(
              emptyLabel!,
              style: context.texts.bodySmall
                  ?.copyWith(color: palette.onSurfaceMuted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final line in lines)
                  Padding(
                    padding: EdgeInsets.only(bottom: m.spaceXs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('· ',
                            style: context.texts.bodySmall
                                ?.copyWith(color: tone ?? palette.onSurfaceMuted)),
                        Expanded(
                          child: Text(line, style: context.texts.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ObservationsCard extends StatelessWidget {
  const _ObservationsCard({required this.result});

  final PatientSummaryPresentation result;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    if (result.vitals.isEmpty && result.news2Line == null) {
      return SectionCard(
        title: 'Latest observations',
        leading: Icon(Icons.monitor_heart_outlined,
            size: 20, color: palette.onSurfaceMuted),
        child: Text(
          'No vital signs recorded yet.',
          style:
              context.texts.bodySmall?.copyWith(color: palette.onSurfaceMuted),
        ),
      );
    }

    return SectionCard(
      title: 'Latest observations',
      leading: Icon(Icons.monitor_heart_outlined,
          size: 20, color: palette.onSurfaceMuted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (result.vitals.isNotEmpty)
            Wrap(
              spacing: m.spaceSm,
              runSpacing: m.spaceXs,
              children: <Widget>[
                for (final vital in result.vitals)
                  MetricChip(label: vital.label, value: vital.value),
              ],
            ),
          if (result.news2Line case final news2?) ...<Widget>[
            SizedBox(height: m.spaceSm),
            Text(news2, style: context.texts.labelMedium),
          ],
        ],
      ),
    );
  }
}

class _VisitsCard extends StatelessWidget {
  const _VisitsCard({required this.visits});

  final List<({String when, String summary})> visits;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    if (visits.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      title: 'Recent visits',
      leading: Icon(Icons.history, size: 20, color: palette.onSurfaceMuted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final visit in visits)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    visit.when,
                    style: context.texts.labelSmall
                        ?.copyWith(color: palette.onSurfaceMuted),
                  ),
                  Text(visit.summary, style: context.texts.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
