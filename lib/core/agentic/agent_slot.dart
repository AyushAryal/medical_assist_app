import 'package:flutter/widgets.dart';

import 'agent_scope.dart';
import 'agent_surface.dart';

/// Where a screen offers its [surface] to whatever agent is installed.
///
/// It asks [AgentScope] for the installed [AgentHost] and renders that host's
/// affordance. When no host is installed — the module was removed, or is off —
/// it renders nothing. A screen therefore carries the slot unconditionally: it
/// lights up when the module is present and disappears cleanly when it is not.
///
/// This is the whole reason a screen can publish an [AgentSurface] without
/// depending on the agentic module: it talks to core's [AgentScope]/[AgentHost]
/// seam, never to the module.
class AgentSlot extends StatelessWidget {
  const AgentSlot({super.key, required this.surface});

  final AgentSurface surface;

  @override
  Widget build(BuildContext context) {
    final host = AgentScope.of(context);
    return host?.affordanceFor(context, surface) ?? const SizedBox.shrink();
  }
}
