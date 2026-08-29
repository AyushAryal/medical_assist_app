import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/modules/entitlements.dart';
import '../../core/modules/module_registry.dart';
import '../../core/modules/workflow_preferences.dart';

/// The single gate for the recall module: licensed AND switched on by the
/// clinic. Every entry point asks this; remove `lib/features/recall/` and its
/// call sites and the app is unchanged.
abstract final class RecallModule {
  static bool isVisible(BuildContext context) =>
      context.watch<Entitlements>().has(ModuleId.recall) &&
      context.watch<WorkflowPreferences>().isEnabled(ModuleId.recall);
}
