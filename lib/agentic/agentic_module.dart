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
///
/// It breathes the same accent → primary pulse as [AiSparkleIcon] (the AI
/// bubble's star), so the mic reads as the same living AI element — a glyph
/// that pulses from purple to blue, not a flat icon.
class _GuidedDictationAffordance extends StatefulWidget {
  const _GuidedDictationAffordance({required this.surface});

  final AgentSurface surface;

  @override
  State<_GuidedDictationAffordance> createState() =>
      _GuidedDictationAffordanceState();
}

class _GuidedDictationAffordanceState extends State<_GuidedDictationAffordance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    IconButton mic(Color color, double glow) => IconButton(
          tooltip: 'Dictate these fields',
          onPressed: () => GuidedDictationSheet.show(context, widget.surface),
          icon: Icon(
            Icons.mic_none,
            color: color,
            shadows: <Shadow>[
              Shadow(color: color.withValues(alpha: 0.55), blurRadius: glow),
            ],
          ),
        );

    if (reduced) return mic(palette.accent, 8);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        // The same pulse as the sparkle: accent (purple) → primary (blue).
        return mic(Color.lerp(palette.accent, palette.primary, t)!, 7 + t * 5);
      },
    );
  }
}
