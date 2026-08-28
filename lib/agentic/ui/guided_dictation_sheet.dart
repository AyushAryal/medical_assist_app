import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/agentic/agent_surface.dart';
import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../drivers/guided_dictation_controller.dart';
import '../drivers/spoken_value.dart';

// AppBootstrap is a ChangeNotifier, which a plain Provider cannot carry, and a
// modal sheet is pushed outside the calling context's providers anyway — so it
// is read once at the call site and handed to the sheet directly.

/// The hands-free guided flow, field by field over an [AgentSurface].
///
/// One utterance at a time: tap to listen, the value is transcribed on-device,
/// parsed and *proposed* into the field behind the sheet (never committed —
/// the clinician still reviews and saves). "next" confirms and advances,
/// "redo" re-dictates; the same actions are also buttons, so the flow works
/// when a hand is free and degrades to taps when the mic mishears.
///
/// The voice path needs a real microphone and an installed speech model, so it
/// is exercised on device rather than in the widget tests; the state machine it
/// drives ([GuidedDictationController]) is unit-tested on its own.
class GuidedDictationSheet extends StatefulWidget {
  const GuidedDictationSheet({
    super.key,
    required this.surface,
    required this.bootstrap,
  });

  final AgentSurface surface;
  final AppBootstrap bootstrap;

  static Future<void> show(BuildContext context, AgentSurface surface) {
    final bootstrap = context.read<AppBootstrap>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          GuidedDictationSheet(surface: surface, bootstrap: bootstrap),
    );
  }

  @override
  State<GuidedDictationSheet> createState() => _GuidedDictationSheetState();
}

class _GuidedDictationSheetState extends State<GuidedDictationSheet> {
  static const _parser = SpokenValueParser();
  late final GuidedDictationController _controller =
      GuidedDictationController(widget.surface);

  bool _listening = false;
  bool _working = false;
  String _message = 'Tap the mic and say the value.';
  String? _heard;

  Future<void> _toggleMic() async {
    final bootstrap = widget.bootstrap;
    if (!_listening) {
      final started = await bootstrap.dictation.start();
      if (!mounted) return;
      setState(() {
        _listening = started;
        _message = started ? 'Listening…' : 'Could not start the microphone.';
      });
      return;
    }

    setState(() {
      _listening = false;
      _working = true;
    });
    try {
      final capture = await bootstrap.dictation.stop();
      if (capture == null) throw StateError('nothing recorded');
      final result = await bootstrap.transcription.transcribe(capture.file);
      _apply(_parser.parse(result.text), heard: result.text);
    } on Object {
      if (mounted) {
        setState(() => _message = 'Did not catch that — try again.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _command(DictationCommand command) =>
      _apply(CommandUtterance(command));

  void _apply(Utterance utterance, {String? heard}) {
    final outcome = _controller.apply(utterance);
    final state = _controller.state;
    if (state.complete) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _heard = heard;
      _message = switch (outcome) {
        GuidedOutcome.proposed =>
          'Proposed for ${state.field?.label}. Say "next" or "redo".',
        GuidedOutcome.unclear => 'Did not catch a value — say it again.',
        GuidedOutcome.redone => 'Cleared. Say the ${state.field?.label}.',
        _ => 'Now: ${state.field?.label}${_unit(state.field)}.',
      };
    });
  }

  String _unit(AgentField? field) =>
      field?.unit == null ? '' : ' (${field!.unit})';

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final state = _controller.state;
    final field = state.field;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(m.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const AiSparkleIcon(size: 20),
                SizedBox(width: m.spaceSm),
                Expanded(
                  child: Text('Guided dictation',
                      style: context.texts.titleMedium),
                ),
                Text('${state.index + 1} / ${state.total}',
                    style: context.texts.labelSmall),
              ],
            ),
            SizedBox(height: m.spaceLg),
            Text(field?.label ?? '', style: context.texts.displaySmall),
            if (field?.unit != null)
              Text(field!.unit!, style: context.texts.bodySmall),
            SizedBox(height: m.spaceMd),
            Text(_message, style: context.texts.bodyMedium),
            if (_heard != null)
              Text('Heard: "$_heard"',
                  style: context.texts.labelSmall
                      ?.copyWith(color: palette.onSurfaceMuted)),
            SizedBox(height: m.spaceLg),
            FilledButton.icon(
              onPressed: _working ? null : _toggleMic,
              icon: Icon(_listening ? Icons.stop : Icons.mic),
              label: Text(_listening ? 'Stop' : 'Listen'),
            ),
            SizedBox(height: m.spaceSm),
            Wrap(
              spacing: m.spaceSm,
              alignment: WrapAlignment.center,
              children: <Widget>[
                TextButton(
                    onPressed: () => _command(DictationCommand.redo),
                    child: const Text('Redo')),
                TextButton(
                    onPressed: () => _command(DictationCommand.back),
                    child: const Text('Back')),
                TextButton(
                    onPressed: () => _command(DictationCommand.skip),
                    child: const Text('Skip')),
                TextButton(
                    onPressed: () => _command(DictationCommand.next),
                    child: const Text('Next')),
                TextButton(
                    onPressed: () => _command(DictationCommand.stop),
                    child: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
