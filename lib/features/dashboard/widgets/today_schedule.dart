import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design.dart';
import '../../../core/routing/app_router.dart';
import '../../../data/models/appointment.dart';
import '../../appointments/appointments.dart';
import '../dashboard_controller.dart';

class TodaySchedule extends StatelessWidget {
  const TodaySchedule({super.key, required this.dashboard});

  final DashboardController dashboard;

  /// Whether the panel will render anything. The dashboard checks this before
  /// listing the panel in [SplitColumns], which spaces every listed child —
  /// an internally-collapsed panel would leave its spacer behind as a gap.
  static bool hasContent(DashboardController dashboard) =>
      dashboard.todaySchedule.any((i) => !i.appointment.status.isFinished);

  @override
  Widget build(BuildContext context) {
    if (!hasContent(dashboard)) return const SizedBox.shrink();

    final m = context.metrics;
    final upcoming = dashboard.todaySchedule
        .where((i) => !i.appointment.status.isFinished)
        .take(4)
        .toList();

    return SectionCard(
      title: "Today's clinic",
      subtitle: '${dashboard.remainingToday} still to see',
      leading: const Icon(Icons.event_outlined, size: 20),
      trailing: TextButton(
        onPressed: () => context.go(Routes.schedule),
        child: const Text('All'),
      ),
      child: Column(
        children: <Widget>[
          for (final (i, item) in upcoming.indexed)
            Padding(
              // Between tiles only — no dead band under the last one.
              padding: EdgeInsets.only(
                bottom: i == upcoming.length - 1 ? 0 : m.spaceSm,
              ),
              child: AppointmentTile(
                appointment: item.appointment,
                patient: item.patient,
                // Tapping a specific appointment opens that patient's chart
                // (a real drill-in with a back button), the same as tapping a
                // recent patient — rather than dropping onto the schedule tab
                // and making the user find them again. "All" still switches
                // to the schedule tab to see everything.
                onTap: () => context.push(Routes.chartFor(item.patient.id)),
              ),
            ),
        ],
      ),
    );
  }
}
