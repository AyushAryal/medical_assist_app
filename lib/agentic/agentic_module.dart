import 'package:flutter/material.dart';

import '../core/agentic/agent_host.dart';
import '../core/agentic/agent_surface.dart';
import '../core/design/design.dart';
import 'ui/guided_dictation_sheet.dart';

/// The agentic module: the removable capability that operates a screen's
/// [AgentSurface].
///
/// This is the only class the composition root references to install the
/// module — `Provider<AgentHost?>(create: (_) => const AgentModuleHost())`.
/// Nothing else in the app imports anything under `lib/agentic/`, so deleting
/// this folder and that one provider leaves the app building and running with
/// every [AgentSlot] simply empty. A `test/agentic/removability_test.dart`
/// enforces that one-way dependency.
///
/// Today it installs one driver — the guided voice flow. A larger local or
/// cloud model would be a second driver behind the same [affordanceFor] seam,
/// operating the very same surfaces the screens already publish.
class AgentModuleHost implements AgentHost {
  const AgentModuleHost();

  @override
  Widget? affordanceFor(BuildContext context, AgentSurface surface) {
    // Nothing to offer for a display-only surface.
    if (surface.fillable.isEmpty) return null;
    return _GuidedDictationAffordance(surface: surface);
  }
}

/// The control a screen's [AgentSlot] renders — a mic that starts the guided
/// flow over the surface.
class _GuidedDictationAffordance extends StatelessWidget {
  const _GuidedDictationAffordance({required this.surface});

  final AgentSurface surface;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    // A gently glowing mic, so the AI voice entry reads as the special thing
    // it is rather than one more app-bar icon.
    return Padding(
      padding: EdgeInsets.only(right: m.spaceXs),
      child: AiGlowBorder(
        active: true,
        borderRadius: BorderRadius.circular(m.radiusMd),
        child: IconButton(
          tooltip: 'Dictate these fields',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.mic_none, color: context.palette.primary),
          onPressed: () => GuidedDictationSheet.show(context, surface),
        ),
      ),
    );
  }
}
