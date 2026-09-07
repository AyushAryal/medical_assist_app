import 'package:flutter/widgets.dart';

import 'agent_host.dart';

/// Makes an [AgentHost] available to the [AgentSlot]s below it.
///
/// The agentic module installs one of these at the composition root. When the
/// module is absent there is simply no `AgentScope` in the tree, and
/// [AgentScope.of] returns null — so an [AgentSlot] never depends on the scope
/// existing and the app runs unchanged without the module.
class AgentScope extends InheritedWidget {
  const AgentScope({super.key, required this.host, required super.child});

  final AgentHost? host;

  /// The installed host, or null when no module is present.
  static AgentHost? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgentScope>()?.host;

  @override
  bool updateShouldNotify(AgentScope oldWidget) => host != oldWidget.host;
}
