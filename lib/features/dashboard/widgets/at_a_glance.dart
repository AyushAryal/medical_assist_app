import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../dashboard_controller.dart';

/// Compact counts plus a week-at-a-glance bar chart.
///
/// Deliberately below the actionable sections: these numbers are context for
/// the day, not tasks, and putting them at the top would push the work down.
class AtAGlance extends StatelessWidget {
  const AtAGlance({super.key, required this.dashboard});

  final DashboardController dashboard;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceLg),
      child: SectionCard(
        title: 'This week',
        leading: const Icon(Icons.insights_outlined, size: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: m.spaceSm,
              runSpacing: m.spaceSm,
              children: <Widget>[
                _Stat(
                  label: 'Unsigned',
                  value: '${dashboard.draftNoteCount}',
                  tone: dashboard.draftNoteCount > 0
                      ? palette.caution
                      : palette.normal,
                  explanation: MetricExplanation(
                    title: 'Unsigned notes',
                    summary:
                        'Notes that have been started but not signed, '
                        'across every patient and every day — not just today.',
                    method: const <String>[
                      'Every clinical note in the database is counted whose '
                          'status is still draft.',
                      'A note becomes signed only when a clinician signs it, '
                          'which locks it and makes it the final record.',
                      'There is no time limit on this count: an unsigned note '
                          'from three weeks ago is still an unfinished record, '
                          'and hiding it after a day would be the opposite of '
                          'useful.',
                    ],
                    total: '${dashboard.draftNoteCount} unsigned',
                    caveat:
                        'An empty note that was opened and abandoned '
                        'counts here too. Opening it and signing or discarding '
                        'it is what clears it.',
                  ),
                ),
                _Stat(
                  label: 'Seen today',
                  value: '${dashboard.todayEncounterCount}',
                  tone: palette.primary,
                  explanation: MetricExplanation(
                    title: 'Seen today',
                    summary: 'Encounters started today at the active clinic.',
                    method: const <String>[
                      'Counts encounters whose start time falls between '
                          'midnight this morning and midnight tonight.',
                      'Filtered to the clinic currently selected at the top of '
                          'this screen — switching clinic changes this number.',
                      'It counts encounters, not patients: someone seen twice '
                          'in a day counts twice.',
                      'Status is not considered, so a visit still in progress '
                          'is already included.',
                    ],
                    total: '${dashboard.todayEncounterCount} today',
                  ),
                ),
                _Stat(
                  label: 'Observations',
                  value: '${dashboard.todayVitalsCount}',
                  tone: palette.accent,
                  explanation: MetricExplanation(
                    title: 'Observation sets today',
                    summary:
                        'Sets of vital signs recorded today, across all '
                        'clinics.',
                    method: const <String>[
                      'Counts rows of recorded observations with today’s date.',
                      'One set is one visit to the bedside, however many '
                          'individual values it contains — a blood pressure '
                          'and a temperature taken together are one set.',
                      'Unlike "seen today" this is not filtered by clinic.',
                    ],
                    total: '${dashboard.todayVitalsCount} sets',
                  ),
                ),
                _Stat(
                  label: 'Patients',
                  value: '${dashboard.patientCount}',
                  tone: palette.onSurfaceMuted,
                  explanation: MetricExplanation(
                    title: 'Registered patients',
                    summary: 'Everyone on this device’s register, ever.',
                    method: const <String>[
                      'Counts every patient record that has not been deleted.',
                      'It is a total, not an activity measure: it does not '
                          'shrink when someone stops attending, and it counts '
                          'patients registered at any clinic.',
                      'Any duplicate records that exist are counted twice — '
                          'the duplicate check on registration is what keeps '
                          'that number honest.',
                    ],
                    total: '${dashboard.patientCount} records',
                  ),
                ),
              ],
            ),
            if (dashboard.weekActivity.isNotEmpty) ...<Widget>[
              SizedBox(height: m.spaceLg),
              Row(
                children: <Widget>[
                  Text('Encounters per day', style: context.texts.labelSmall),
                  InfoDot(
                    explanation: MetricExplanation(
                      title: 'Encounters per day',
                      summary:
                          'How many encounters were started on each of '
                          'the last seven days, oldest on the left.',
                      method: const <String>[
                        'Each bar counts encounters started on that calendar '
                            'day, across every clinic.',
                        'The seven days end with today, so today’s bar is '
                            'still filling and will almost always look short.',
                        'Bars are scaled to the busiest day in the window, so '
                            'the tallest bar is always full height — the shape '
                            'shows relative load, not an absolute count.',
                        'The letters are weekday initials, which is why two '
                            'of them are T and two are S.',
                      ],
                      confidence: ExplainConfidence.measured,
                      caveat:
                          'Seven days is enough to see whether this week '
                          'is busier than usual. It is not enough to read a '
                          'trend from, and it is not analytics.',
                    ),
                  ),
                ],
              ),
              SizedBox(height: m.spaceSm),
              MiniBarChart(bars: dashboard.weekActivity),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.tone,
    this.explanation,
  });

  final String label;
  final String value;
  final Color tone;

  /// What exactly is being counted. A four-word label cannot distinguish
  /// "encounters started today at this clinic" from "patients seen today
  /// anywhere", and the difference is the whole meaning of the number.
  final MetricExplanation? explanation;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.spaceMd, vertical: m.spaceSm),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            style: context.texts.titleMedium?.copyWith(
              color: tone,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(width: m.spaceXs + 2),
          Text(label, style: context.texts.labelSmall),
          if (explanation case final explanation?)
            InfoDot(
              explanation: explanation,
              semanticLabel: 'What "$label" counts',
            ),
        ],
      ),
    );
  }
}
