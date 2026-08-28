import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/patient.dart';
import '../dashboard_controller.dart';

class RecentPatients extends StatelessWidget {
  const RecentPatients({super.key, required this.dashboard});

  final DashboardController dashboard;

  @override
  Widget build(BuildContext context) {
    if (dashboard.recentPatients.isEmpty) {
      return SectionCard(
        title: 'Get started',
        leading: const Icon(Icons.waving_hand_outlined, size: 20),
        child: EmptyState(
          icon: Icons.person_add_alt,
          title: 'No patients yet',
          message:
              'Register a patient to begin, or load demo data from '
              'Settings to explore the app.',
          actionLabel: 'Register patient',
          onAction: () => context.push(Routes.patientNew),
          compact: true,
        ),
      );
    }

    return SectionCard(
      title: 'Recent patients',
      leading: const Icon(Icons.history, size: 20),
      trailing: TextButton(
        onPressed: () => context.go(Routes.patients),
        child: const Text('All'),
      ),
      child: Column(
        children: dashboard.recentPatients.take(6).map((patient) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => context.push(Routes.chartFor(patient.id)),
            leading: PatientAvatar(
              initials: patient.initials,
              seed: patient.id,
              radius: 18,
              badge: patient.allergyStatus == AllergyStatus.hasAllergies
                  ? AvatarBadge(
                      icon: Icons.priority_high,
                      tone: context.palette.critical,
                    )
                  : null,
            ),
            title: Text(
              patient.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              patient.identityLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              Fmt.relative(patient.lastSeenAt),
              style: context.texts.labelSmall,
            ),
          );
        }).toList(),
      ),
    );
  }
}
