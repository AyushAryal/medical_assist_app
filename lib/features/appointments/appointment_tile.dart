import 'package:flutter/material.dart';

import '../../clinical/insights/schedule_insights.dart';
import '../../core/design/design.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/appointment.dart';
import '../../data/models/encounter.dart';
import '../../data/models/patient.dart';

/// One row in a schedule.
///
/// The time sits in a fixed-width gutter so a column of appointments reads as
/// a timeline rather than a ragged list.
class AppointmentTile extends StatelessWidget {
  const AppointmentTile({
    super.key,
    required this.appointment,
    required this.patient,
    this.onTap,
    this.trailing,
    this.waitEstimate,
  });

  final Appointment appointment;
  final Patient patient;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Roughly how long until this patient is called, from how long this clinic's
  /// consultations actually take. Null when they are not waiting, or when
  /// nobody is in front of them.
  final WaitEstimate? waitEstimate;

  PillTone get _tone => switch (appointment.status) {
        AppointmentStatus.arrived => PillTone.caution,
        AppointmentStatus.inProgress => PillTone.info,
        AppointmentStatus.completed => PillTone.normal,
        AppointmentStatus.noShow => PillTone.critical,
        AppointmentStatus.cancelled => PillTone.neutral,
        _ => PillTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final waiting = appointment.waitingFor;
    final isDone = appointment.status.isFinished;

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(m.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: m.spaceMd,
            vertical: m.spaceMd,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // Fixed time gutter — keeps the column aligned.
              SizedBox(
                width: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      Fmt.time(appointment.scheduledAt),
                      style: context.texts.titleSmall?.copyWith(
                        color: isDone ? palette.onSurfaceMuted : palette.onSurface,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    Text(
                      '${appointment.durationMinutes}m',
                      style: context.texts.labelSmall,
                    ),
                  ],
                ),
              ),
              Container(
                width: 3,
                height: 38,
                margin: EdgeInsets.only(right: m.spaceMd),
                decoration: BoxDecoration(
                  color: isDone
                      ? palette.outline
                      : palette.avatarToneFor(patient.id),
                  borderRadius: BorderRadius.circular(m.radiusXs / 2),
                ),
              ),
              PatientAvatar(
                initials: patient.initials,
                seed: patient.id,
                radius: 18,
              ),
              SizedBox(width: m.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      patient.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: appointment.status ==
                                AppointmentStatus.cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    Text(
                      appointment.reason ?? appointment.type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall,
                    ),
                    if (waitEstimate case final estimate?)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.hourglass_empty,
                            size: 12,
                            color: palette.onSurfaceMuted,
                          ),
                          SizedBox(width: m.spaceXs / 2),
                          Text(
                            'about ${estimate.wait.inMinutes} min',
                            style: context.texts.labelSmall,
                          ),
                          SizedBox(width: m.spaceXs / 2),
                          const AiBadge(label: 'Estimate', dense: true),
                          InfoDot(
                            explanation:
                                WaitTimeEstimator.explain(estimate),
                            semanticLabel: 'How this wait was estimated',
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              SizedBox(width: m.spaceSm),
              if (trailing != null)
                trailing!
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    StatusPill(
                      label: appointment.status.label,
                      tone: _tone,
                      dense: true,
                    ),
                    if (waiting != null)
                      Padding(
                        padding: EdgeInsets.only(top: m.spaceXs),
                        child: Text(
                          'waiting ${waiting.inMinutes}m',
                          style: context.texts.labelSmall?.copyWith(
                            color: waiting.inMinutes > 30
                                ? palette.critical
                                : palette.onSurfaceMuted,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
