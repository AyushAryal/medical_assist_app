import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/modules/entitlements.dart';
import '../../core/modules/module_registry.dart';
import '../../core/modules/workflow_preferences.dart';

/// Shows which modules the current licence grants.
///
/// Round 1 grants everything. The screen exists now so the gating pathway is
/// exercised from the start — a subscription bolted on later tends to be
/// bypassable in exactly the places nobody tested.
class ModulesScreen extends StatelessWidget {
  const ModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entitlements = context.watch<Entitlements>();
    final workflows = context.watch<WorkflowPreferences>();
    final m = context.metrics;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Modules')),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.all(m.spaceLg),
          children: <Widget>[
            SectionCard(
              title: 'Current plan',
              leading: const Icon(Icons.workspace_premium_outlined, size: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      StatusPill(
                        label: entitlements.plan.label,
                        tone: PillTone.info,
                      ),
                      SizedBox(width: m.spaceSm),
                      Text(
                        '${entitlements.granted.length} of '
                        '${ModuleRegistry.all.length} modules',
                        style: context.texts.bodySmall,
                      ),
                    ],
                  ),
                  SizedBox(height: m.spaceMd),
                  Text(
                    'Licensing is not yet enforced. Module gating controls '
                    'which features appear; it is not a security boundary and '
                    'never withholds a record from the clinician treating the '
                    'patient.',
                    style: context.texts.bodySmall,
                  ),
                ],
              ),
            ),
            SizedBox(height: m.spaceMd),
            if (WorkflowPreferences.configurable.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: m.spaceMd),
                child: SectionCard(
                  title: 'Clinic workflows',
                  subtitle: 'Optional features this clinic turns on for itself.',
                  child: Column(
                    children: WorkflowPreferences.configurable.map((id) {
                      final module = ModuleRegistry.describe(id);
                      final licensed = entitlements.has(id);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          module.icon,
                          color: licensed
                              ? context.palette.primary
                              : context.palette.onSurfaceMuted,
                        ),
                        title: Text(module.name),
                        subtitle: Text(module.description),
                        trailing: licensed
                            ? Switch(
                                value: workflows.isEnabled(id),
                                onChanged: (v) => workflows.setEnabled(id, v),
                              )
                            : const StatusPill(
                                label: 'Locked',
                                tone: PillTone.neutral,
                                icon: Icons.lock_outline,
                                dense: true,
                              ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ...ModuleTier.values.map((tier) {
              // Clinic-configurable modules are governed in the card above, so
              // they do not also appear in the licence list.
              final modules = ModuleRegistry.ofTier(tier)
                  .where((id) => !ModuleRegistry.describe(id).clinicConfigurable)
                  .toList();
              if (modules.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(bottom: m.spaceMd),
                child: SectionCard(
                  title: tier.label,
                  child: Column(
                    children: modules.map((id) {
                      final module = ModuleRegistry.describe(id);
                      final granted = entitlements.has(id);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          module.icon,
                          color: granted
                              ? context.palette.primary
                              : context.palette.onSurfaceMuted,
                        ),
                        title: Text(module.name),
                        subtitle: Text(module.description),
                        trailing: granted
                            ? const StatusPill(
                                label: 'Included',
                                tone: PillTone.normal,
                                dense: true,
                              )
                            : const StatusPill(
                                label: 'Locked',
                                tone: PillTone.neutral,
                                icon: Icons.lock_outline,
                                dense: true,
                              ),
                      );
                    }).toList(),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
