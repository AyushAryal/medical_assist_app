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
    final palette = context.palette;
    // The mic glyph itself is the accent, gradient-tinted and softly glowing,
    // so the AI voice entry reads as the special thing it is rather than one
    // more app-bar icon — no ring around it.
    return IconButton(
      tooltip: 'Dictate these fields',
      onPressed: () => GuidedDictationSheet.show(context, surface),
      icon: Icon(
        Icons.mic_none,
        color: palette.primary,
        // A soft halo of the same colour behind the glyph — the icon glows.
        shadows: <Shadow>[
          Shadow(color: palette.primary.withValues(alpha: 0.6), blurRadius: 9),
          Shadow(color: palette.accent.withValues(alpha: 0.35), blurRadius: 16),
        ],
      ),
    );
  }
}
