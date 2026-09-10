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

  @override
  Widget build(BuildContext context) {
    if (dashboard.todaySchedule.isEmpty) return const SizedBox.shrink();

    final m = context.metrics;
    final upcoming = dashboard.todaySchedule
        .where((i) => !i.appointment.status.isFinished)
        .take(4)
        .toList();
    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceLg),
      child: SectionCard(
        title: "Today's clinic",
        subtitle: '${dashboard.remainingToday} still to see',
        leading: const Icon(Icons.event_outlined, size: 20),
        trailing: TextButton(
          onPressed: () => context.go(Routes.schedule),
          child: const Text('All'),
        ),
        child: Column(
          children: <Widget>[
            for (final item in upcoming)
              Padding(
                padding: EdgeInsets.only(bottom: m.spaceSm),
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
      ),
    );
  }
}
