import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../clinical/news2.dart';
import '../../../core/design/design.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../dashboard_controller.dart';

/// Patients whose observations today scored medium or high on NEWS2.
///
/// Hidden entirely when empty — an always-present "nothing to see" card trains
/// people to stop looking at the place where warnings appear.
class NeedsAttention extends StatelessWidget {
  const NeedsAttention({super.key, required this.dashboard});

  final DashboardController dashboard;

  @override
  Widget build(BuildContext context) {
    if (dashboard.flagged.isEmpty) return const SizedBox.shrink();

    final m = context.metrics;
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceMd),
      child: Container(
        decoration: BoxDecoration(
          color: palette.criticalSubtle,
          borderRadius: BorderRadius.circular(m.radiusMd),
        ),
        padding: EdgeInsets.all(m.spaceLg),
        // The tinted background is a DecoratedBox; the ListTiles below paint
        // their own background and ink on the nearest Material ancestor, so
        // without one of their own here that would be the Scaffold, hidden
        // behind this tint. A transparent Material gives them a surface to
        // draw on without covering the tint.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.priority_high, color: palette.critical, size: 20),
                  SizedBox(width: m.spaceSm),
                  Expanded(
                    child: Text(
                      'Needs a second look',
                      style: context.texts.titleMedium?.copyWith(
                        color: palette.critical,
                      ),
                    ),
                  ),
                  InfoDot(
                    explanation: MetricExplanation(
                      title: 'Needs a second look',
                      summary:
                          'Patients whose observations today produced an '
                          'elevated early warning score.',
                      method: const <String>[
                        'Only observation sets recorded today are considered.',
                        'A set qualifies when its NEWS2 score reached the medium '
                            'or high band, or when any single parameter scored '
                            '3 on its own.',
                        'One row per patient — their highest-scoring set. Six '
                            'rows for the same person would bury everyone else.',
                        'Patients NEWS2 cannot score — under 16, or pregnant, or '
                            'with an incomplete observation set — never appear '
                            'here, because no score was produced for them.',
                        'The whole section is hidden when it is empty, rather '
                            'than showing "nothing to see". A panel that is '
                            'usually empty is one people stop looking at.',
                      ],
                      confidence: ExplainConfidence.validated,
                      source: 'Royal College of Physicians, NEWS2 (2017)',
                      caveat:
                          'Absence from this list is not reassurance. A '
                          'patient with no observations recorded today cannot '
                          'appear here, and neither can a child or a pregnant '
                          'patient however unwell they are.',
                    ),
                  ),
                ],
              ),
              SizedBox(height: m.spaceXs),
              Text(
                'Elevated early warning score recorded today',
                style: context.texts.bodySmall,
              ),
              SizedBox(height: m.spaceSm),
              for (final item in dashboard.flagged)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => context.push(Routes.chartFor(item.patient.id)),
                  leading: PatientAvatar(
                    initials: item.patient.initials,
                    seed: item.patient.id,
                    radius: 18,
                  ),
                  title: Text(
                    item.patient.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item.patient.identityLine} · '
                    '${Fmt.time(item.vitals.recordedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: StatusPill(
                    label: 'NEWS ${item.vitals.news2Score}',
                    tone:
                        News2Risk.values
                                .where((r) => r.name == item.vitals.news2Risk)
                                .firstOrNull ==
                            News2Risk.high
                        ? PillTone.critical
                        : PillTone.caution,
                    dense: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
