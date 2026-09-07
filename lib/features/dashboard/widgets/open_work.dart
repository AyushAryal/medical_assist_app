import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/encounter.dart';
import '../dashboard_controller.dart';

class OpenWork extends StatelessWidget {
  const OpenWork({super.key, required this.dashboard, required this.onChanged});

  final DashboardController dashboard;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    if (dashboard.openWork.isEmpty && dashboard.draftNoteCount == 0) {
      return const SizedBox.shrink();
    }

    final m = context.metrics;

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceLg),
      child: SectionCard(
        title: 'Unfinished charting',
        subtitle:
            '${dashboard.openWork.length} encounter'
            '${dashboard.openWork.length == 1 ? '' : 's'} to complete',
        leading: const Icon(Icons.edit_note, size: 20),
        child: dashboard.openWork.isEmpty
            ? const EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Nothing outstanding',
                compact: true,
              )
            : Column(
                children: dashboard.openWork.take(6).map((item) {
                  final sections = item.note?.filledSectionCount ?? 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () async {
                      await context.push(
                        Routes.encounterFor(item.encounter.id),
                      );
                      await onChanged();
                    },
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
                      '${item.encounter.type.label} · '
                      '${Fmt.relative(item.encounter.startedAt)}'
                      '${sections > 0 ? ' · $sections/4' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: StatusPill(
                      label: item.encounter.status.label,
                      tone: item.encounter.status == EncounterStatus.completed
                          ? PillTone.info
                          : PillTone.caution,
                      dense: true,
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }
}
