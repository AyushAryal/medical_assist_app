import 'package:flutter/widgets.dart';

import 'agent_surface.dart';

/// The optional capability that operates a screen's [AgentSurface] — a voice
/// flow today, a local or cloud model later.
///
/// This is the seam that keeps the agentic *module* removable. The app core
/// depends only on this interface (and [AgentSlot]/[AgentScope]); it never
/// imports the module. The module implements [AgentHost] and is injected at
/// the composition root. Delete the module and drop that one injection and the
/// app still builds and runs — every [AgentSlot] simply renders nothing.
abstract interface class AgentHost {
  /// The control a screen shows to hand [surface] to the agent — a mic button,
  /// say — or null if this host offers nothing for that surface.
  Widget? affordanceFor(BuildContext context, AgentSurface surface);
}
