import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/design/design.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/repositories/clinical_repository.dart';
import '../dashboard_controller.dart';

/// The single most useful thing on the screen: who is next, and one tap to
/// start seeing them.
class NextUpCard extends StatelessWidget {
  const NextUpCard({super.key, required this.dashboard, required this.onChanged});

  final DashboardController dashboard;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final next = dashboard.nextUp;

    if (next == null) {
      final nothingBooked = dashboard.todaySchedule.isEmpty;
      return Container(
        padding: EdgeInsets.all(m.spaceLg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(m.radiusMd),
          color: palette.primaryContainer,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(m.radiusSm),
              ),
              child: Icon(
                nothingBooked ? Icons.event_available_outlined : Icons.task_alt,
                color: palette.onPrimaryContainer,
              ),
            ),
            SizedBox(width: m.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    nothingBooked
                        ? 'No clinic booked today'
                        : 'Clinic list clear',
                    style: context.texts.titleMedium?.copyWith(
                      color: palette.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    nothingBooked
                        ? 'Book a visit, or see a walk-in straight from a chart.'
                        : 'Everyone booked for today has been seen.',
                    style: context.texts.bodySmall?.copyWith(
                      color: palette.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final appointment = next.appointment;
    final waiting = appointment.waitingFor;

    return Container(
      padding: EdgeInsets.all(m.spaceLg),
      decoration: BoxDecoration(
        color: palette.heroSurface,
        borderRadius: BorderRadius.circular(m.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.arrow_forward, size: 15, color: palette.onHeroSurface),
              SizedBox(width: m.spaceXs + 2),
              Text(
                waiting != null ? 'WAITING NOW' : 'NEXT UP',
                style: context.texts.labelSmall?.copyWith(
                  color: palette.onHeroSurface.withValues(alpha: 0.85),
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                Fmt.time(appointment.scheduledAt),
                style: context.texts.labelLarge?.copyWith(
                  color: palette.onHeroSurface,
                ),
              ),
            ],
          ),
          SizedBox(height: m.spaceMd),
          Text(
            next.patient.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.headlineSmall?.copyWith(
              color: palette.onHeroSurface,
            ),
          ),
          Text(
            <String>[
              next.patient.identityLine,
              if (appointment.reason != null) appointment.reason!,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodySmall?.copyWith(
              color: palette.onHeroSurface.withValues(alpha: 0.85),
            ),
          ),
          if (waiting != null) ...<Widget>[
            SizedBox(height: m.spaceSm),
            Text(
              'Waiting ${waiting.inMinutes} min',
              style: context.texts.labelMedium?.copyWith(
                color: palette.onHeroSurface.withValues(alpha: 0.9),
              ),
            ),
          ],
          SizedBox(height: m.spaceLg),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.onHeroSurface,
                    foregroundColor: palette.heroSurface,
                  ),
                  onPressed: () async {
                    final repository = context.read<ClinicalRepository>();
                    final session = context.read<SessionController>();
                    final encounter = await repository.startFromAppointment(
                      appointment,
                      providerName: session.signatureName,
                    );
                    if (context.mounted) {
                      await context.push(Routes.encounterFor(encounter.id));
                    }
                    await onChanged();
                  },
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Start visit'),
                ),
              ),
              SizedBox(width: m.spaceSm),
              IconButton.filledTonal(
                tooltip: 'Open chart',
                style: IconButton.styleFrom(
                  backgroundColor: palette.onHeroSurface.withValues(
                    alpha: 0.18,
                  ),
                  foregroundColor: palette.onPrimary,
                ),
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: () => context.push(Routes.chartFor(next.patient.id)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
