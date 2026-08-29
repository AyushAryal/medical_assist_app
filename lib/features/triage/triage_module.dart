import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/modules/entitlements.dart';
import '../../core/modules/module_registry.dart';
import '../../core/modules/workflow_preferences.dart';

/// The one place that decides whether triage exists in this install.
///
/// Presence is the AND of two independent gates: the licence must grant the
/// module ([Entitlements]) and the clinic must have switched it on
/// ([WorkflowPreferences]). Every entry point — the dashboard card, the route,
/// any future deep link — asks this, so there is a single truth about whether
/// the feature is here. Remove `lib/features/triage/` and these call sites and
/// the app is unchanged; nothing else depends inward on it.
abstract final class TriageModule {
  static bool isVisible(BuildContext context) =>
      context.watch<Entitlements>().has(ModuleId.triage) &&
      context.watch<WorkflowPreferences>().isEnabled(ModuleId.triage);
}
