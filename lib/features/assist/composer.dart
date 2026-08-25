import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';

/// The composer: the input, its controls, and what was last asked.
///
/// Extracted because it is the busiest part of the screen and it was buried in
/// a `build` method four levels deep, which is where the microphone button
/// went missing once already.
///
/// The AI treatment here is deliberately conditional. The border lights while
/// the field has focus and while dictation is live, and is inert otherwise: a
/// control that shimmers permanently stops meaning anything, and on a clinical
/// screen it reads as an alert.
class AskComposer extends StatelessWidget {
  const AskComposer({
    super.key,
    required this.controller,
    required this.focus,
    required this.listening,
    required this.hasText,
    required this.canSpeak,
    required this.lastAsked,
    this.contextSummary,
    required this.onAsk,
    required this.onClear,
    required this.onStartListening,
    required this.onStopListening,
    required this.onCancelListening,
    required this.onOpenGuide,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool listening;
  final bool hasText;
  final bool canSpeak;
  final String? lastAsked;

  /// What the conversation currently is, from the shared thread — the merged
  /// filters, not the last utterance. Shown because a dialogue whose state is
  /// invisible cannot be corrected, only restarted.
  final String? contextSummary;
  final ValueChanged<String> onAsk;
  final VoidCallback onClear;
  final VoidCallback onStartListening;
  final VoidCallback onStopListening;
  final VoidCallback onCancelListening;
  final VoidCallback onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    // The keyboard already covers the bottom nav bar while it's up, so
    // clearance is only needed in the composer's resting state — adding it
    // unconditionally would push the composer away from the keyboard by the
    // bar's height even while typing, which reads as a stray gap.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomPadding =
        m.spaceMd + (keyboardOpen ? 0 : context.bottomBarClearance);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        m.spaceLg,
        m.spaceSm,
        m.spaceLg,
        bottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if ((contextSummary ?? lastAsked) case final asked? when !listening)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceXs, left: m.spaceSm),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.subdirectory_arrow_right,
                    size: 12,
                    color: palette.onSurfaceMuted,
                  ),
                  SizedBox(width: m.spaceXs),
                  Expanded(
                    child: Text(
                      asked,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall?.copyWith(
                        color: palette.onSurfaceMuted,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onClear,
                    child: Padding(
                      padding: EdgeInsets.all(m.spaceXs / 2),
                      child: Icon(
                        Icons.close,
                        size: 13,
                        color: palette.onSurfaceMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          AiGlowBorder(
            active: listening || focus.hasFocus,
            borderRadius: BorderRadius.circular(m.radiusLg),
            strokeWidth: 1.6,
            child: listening
                // Listening to the *recorder*, not to AppBootstrap.
                // AppBootstrap notifies when the engine changes, not on every
                // audio frame — so the waveform was handed a level that never
                // updated and sat flat, which reads as a dead microphone.
                ? ListenableBuilder(
                    listenable: context.read<AppBootstrap>().dictation,
                    builder: (context, _) => ListeningStrip(
                      level: context
                          .read<AppBootstrap>()
                          .dictation
                          .level
                          .current,
                      onStop: onStopListening,
                      onCancel: onCancelListening,
                    ),
                  )
                : TextField(
                    controller: controller,
                    focusNode: focus,
                    textInputAction: TextInputAction.search,
                    // See the assistant panel for the full reasoning: a
                    // keyboard that keeps a composing buffer replays it, which
                    // puts deleted characters back on screen. `autocorrect:
                    // false` is only a hint and several keyboards ignore it;
                    // this keyboard type turns composing off outright.
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    keyboardType: TextInputType.visiblePassword,
                    onSubmitted: onAsk,
                    decoration: InputDecoration(
                      hintText: lastAsked == null
                          ? 'Ask about the register…'
                          : 'Refine — "only the women" — or ask anew…',
                      filled: true,
                      fillColor: palette.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(m.radiusLg),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(m.radiusLg),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(m.radiusLg),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: IconButton(
                        tooltip: 'What you can ask',
                        icon: const AiSparkleIcon(size: 18),
                        onPressed: onOpenGuide,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (hasText)
                            IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: onClear,
                            ),
                          IconButton(
                            tooltip: canSpeak
                                ? 'Ask by voice'
                                : 'Install a speech model in Settings › '
                                      'Dictation to ask by voice',
                            icon: Icon(
                              Icons.mic_none_outlined,
                              color: canSpeak
                                  ? null
                                  : palette.onSurfaceMuted.withValues(
                                      alpha: 0.4,
                                    ),
                            ),
                            onPressed: canSpeak ? onStartListening : null,
                          ),
                          // Filled, and only once there is something to send.
                          // An always-solid send button on an empty field is
                          // an invitation to press a control that does
                          // nothing.
                          IconButton.filled(
                            tooltip: 'Ask',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            style: hasText
                                ? null
                                : IconButton.styleFrom(
                                    backgroundColor: palette.surfaceMuted,
                                    foregroundColor: palette.onSurfaceMuted,
                                  ),
                            onPressed: () => onAsk(controller.text),
                          ),
                          SizedBox(width: m.spaceXs),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class ListeningStrip extends StatelessWidget {
  const ListeningStrip({
    super.key,
    required this.level,
    required this.onStop,
    required this.onCancel,
  });

  final double level;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return AiGlowBorder(
      active: true,
      child: GlassPanel(
        padding: EdgeInsets.all(m.spaceMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SiriWaveform(level: level, active: true, height: 60),
            SizedBox(height: m.spaceXs),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Listening — say your question',
                    style: context.texts.labelSmall,
                  ),
                ),
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
                FilledButton(onPressed: onStop, child: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
