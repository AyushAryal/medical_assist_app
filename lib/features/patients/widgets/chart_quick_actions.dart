import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design.dart';
import '../../../core/routing/app_router.dart';
import '../../appointments/appointments.dart';
import '../../encounters/encounters.dart';
import '../patient_chart_controller.dart';

/// The three things done most often on an open chart, one tap each.
class ChartQuickActions extends StatelessWidget {
  const ChartQuickActions({super.key, required this.chart});

  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final patient = chart.patient!;
    final open = chart.openEncounter;

    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: () async {
              if (open != null) {
                await context.push(Routes.encounterFor(open.id));
              } else {
                final encounter = await StartEncounterSheet.show(
                  context,
                  patient: patient,
                );
                if (encounter != null && context.mounted) {
                  await context.push(Routes.encounterFor(encounter.id));
                }
              }
              await chart.refresh();
            },
            icon: Icon(open != null ? Icons.play_arrow : Icons.add),
            label: Text(open != null ? 'Resume visit' : 'Start visit'),
          ),
        ),
        SizedBox(width: m.spaceSm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              await context.push(Routes.vitalsFor(patient.id));
              await chart.refresh();
            },
            icon: const Icon(Icons.monitor_heart_outlined),
            label: const Text('Vitals'),
          ),
        ),
        SizedBox(width: m.spaceSm),
        IconButton.filledTonal(
          tooltip: 'Book an appointment',
          icon: const Icon(Icons.event_available_outlined),
          onPressed: () async {
            await BookAppointmentSheet.show(context, patient: patient);
            await chart.refresh();
          },
        ),
      ],
    );
  }
}
