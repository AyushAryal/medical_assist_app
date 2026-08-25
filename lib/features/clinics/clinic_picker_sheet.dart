import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/routing/app_router.dart';
import '../../core/session/session_controller.dart';
import '../../data/models/clinic.dart';

/// Bottom-sheet clinic switcher.
///
/// Reachable from the dashboard app bar in one tap, because a locum working
/// three sites in a week changes this far more often than any other setting,
/// and an encounter filed against the wrong site is a record that cannot be
/// found where anyone will look for it.
class ClinicPickerSheet extends StatelessWidget {
  const ClinicPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<SessionController>.value(
        value: context.read<SessionController>(),
        child: const ClinicPickerSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final m = context.metrics;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Working at', style: context.texts.titleMedium),
            SizedBox(height: m.spaceMd),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: session.clinics.map((clinic) {
                  final isActive = clinic.id == session.activeClinic?.id;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isActive
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isActive
                          ? context.palette.primary
                          : context.palette.onSurfaceMuted,
                    ),
                    title: Text(clinic.name),
                    subtitle: Text(
                      <String>[
                        clinic.type.label,
                        if (clinic.locationLabel.isNotEmpty)
                          clinic.locationLabel,
                      ].join(' · '),
                    ),
                    onTap: () async {
                      await session.setActiveClinic(clinic);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  );
                }).toList(),
              ),
            ),
            SizedBox(height: m.spaceSm),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(Routes.clinics);
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Manage clinics'),
            ),
          ],
        ),
      ),
    );
  }
}
