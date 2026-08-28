import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/agentic/agent_surface.dart';
import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../../core/routing/app_router.dart';
import '../drivers/continuous_dictation_controller.dart';

// AppBootstrap is a ChangeNotifier, which a plain Provider cannot carry, and a
// modal sheet is pushed outside the calling context's providers anyway — so it
// is read once at the call site and handed to the sheet directly.

/// Hands-free vitals entry. Tap start once and speak the set with a pause
/// between values — "BP one-twenty over eighty" … "pulse eighty-eight" … "skip
/// glucose" … "done". Each phrase is transcribed on device and staged in a live
/// checklist; the mic keeps listening between phrases, so nothing needs tapping.
/// Nothing reaches the form until the clinician taps Approve & fill, and every
/// value is range-checked, so an impossible reading is refused not written.
///
/// The routing, sanitising and status machine are unit-tested; the audio and
/// the pause detection run on device.
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
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      builder: (_) =>
          GuidedDictationSheet(surface: surface, bootstrap: bootstrap),
    );
  }

  @override
  State<GuidedDictationSheet> createState() => _GuidedDictationSheetState();
}

class _GuidedDictationSheetState extends State<GuidedDictationSheet> {
  late final ContinuousDictationController _controller =
      ContinuousDictationController(widget.surface);

  /// True while a continuous listening session is running (across phrases).
  bool _session = false;

  /// True while the mic is actually open (false during the transcribe gap).
  bool _listening = false;
  bool _working = false;
  double _level = 0;
  bool _sawSpeech = false;
  String? _heard;
  Timer? _levelTimer;

  static const _silenceStop = Duration(milliseconds: 1300);

  @override
  void dispose() {
    _levelTimer?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() => _session = true);
    _beginListen();
  }

  void _stop() {
    _session = false;
    if (_listening) {
      _capturePhrase();
    } else {
      setState(() {});
    }
  }

  Future<void> _beginListen() async {
    final started = await widget.bootstrap.dictation.start();
    if (!mounted) return;
    if (!started) {
      setState(() => _session = false);
      return;
    }
    setState(() {
      _listening = true;
      _sawSpeech = false;
      _level = 0;
    });
    _levelTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted || !_listening) return;
      final level = widget.bootstrap.dictation.level;
      if (level.isSpeaking) _sawSpeech = true;
      setState(() => _level = level.current);
      // A pause after speech ends the phrase — no button.
      if (_sawSpeech && level.silenceRun >= _silenceStop) _capturePhrase();
    });
  }

  Future<void> _capturePhrase() async {
    _levelTimer?.cancel();
    if (!_listening) return;
    setState(() {
      _listening = false;
      _working = true;
    });
    try {
      final capture = await widget.bootstrap.dictation.stop();
      if (capture == null) throw StateError('nothing recorded');
      final result = await widget.bootstrap.transcription.transcribe(
        capture.file,
      );
      // Collapse the token repetition tiny models emit on short/quiet audio
      // ("21 21 21" -> "21") before parsing.
      final text = ContinuousDictationController.cleanTranscript(result.text);
      _controller.applyTranscript(text);
      if (mounted) {
        setState(() => _heard = text.isEmpty ? null : text);
      }
    } on Object {
      if (mounted) setState(() => _heard = 'Did not catch that.');
    } finally {
      if (mounted) {
        setState(() => _working = false);
        // Keep listening for the next value unless the session ended or the
        // set is complete.
        if (_session && !_controller.complete) {
          _beginListen();
        } else {
          setState(() => _session = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    if (!widget.bootstrap.canTranscribe) return _NeedsModel(metrics: m);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(context),
            SizedBox(height: m.spaceMd),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    for (final entry in _controller.entries)
                      _PreviewRow(
                        entry: entry,
                        isNext: !_controller.complete &&
                            entry.field.id == _controller.current?.id,
                        listening: _session,
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: m.spaceMd),
            _controls(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final m = context.metrics;
    return Row(
      children: <Widget>[
        const AiSparkleIcon(size: 20),
        SizedBox(width: m.spaceSm),
        Text('Voice entry', style: context.texts.titleMedium),
        const Spacer(),
        Text(
          '${_controller.filledCount} / ${_controller.total}',
          style: context.texts.labelMedium,
        ),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final active = _session || _working;
    final filled = _controller.filledCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A live audio plot while the session runs, so a working mic is
        // obvious; the glow marks the AI feature at work.
        AiGlowBorder(
          active: active,
          borderRadius: BorderRadius.circular(m.radiusMd),
          child: Container(
            height: 60,
            padding: EdgeInsets.symmetric(horizontal: m.spaceMd),
            alignment: Alignment.center,
            child: _listening
                ? SiriWaveform(level: _level.clamp(0.05, 1.0), active: true)
                : Text(
                    _working
                        ? 'Reading what you said…'
                        : _heard != null
                            ? 'Heard: "$_heard"'
                            : 'Tap start, then say each value with a pause '
                                'between — "BP 120 over 80", "pulse 88", '
                                '"skip glucose", "done".',
                    style: context.texts.labelMedium
                        ?.copyWith(color: palette.onSurfaceMuted),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ),
        SizedBox(height: m.spaceMd),
        if (_session)
          FilledButton.icon(
            onPressed: _working ? null : _stop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          )
        else if (filled == 0)
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.mic),
            label: const Text('Start listening'),
          )
        else ...<Widget>[
          FilledButton.icon(
            onPressed: () {
              _controller.commit();
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.check),
            label: Text('Approve & fill ($filled)'),
          ),
          SizedBox(height: m.spaceSm),
          OutlinedButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.mic),
            label: const Text('Continue'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// One field in the live checklist, its status shown by icon, colour and value.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.entry,
    required this.isNext,
    required this.listening,
  });

  final FieldEntry entry;
  final bool isNext;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    final (IconData icon, Color color) = switch (entry.status) {
      FieldStatus.filled => (Icons.check_circle, palette.normal),
      FieldStatus.skipped => (Icons.remove_circle_outline, palette.onSurfaceMuted),
      FieldStatus.rejected => (Icons.error_outline, palette.caution),
      FieldStatus.pending => (
          isNext && listening ? Icons.graphic_eq : Icons.circle_outlined,
          isNext && listening ? palette.primary : palette.onSurfaceMuted,
        ),
    };

    final trailing = switch (entry.status) {
      FieldStatus.filled => entry.display ?? '',
      FieldStatus.skipped => 'skipped',
      FieldStatus.rejected => 'not caught',
      FieldStatus.pending => '',
    };

    // For a pending field, show its unit and an example of what to say, so the
    // clinician is never guessing — "mmHg · say "120 over 80"".
    String? subtitle;
    if (entry.status == FieldStatus.pending) {
      final parts = <String>[
        if (entry.field.unit != null) entry.field.unit!,
        if (entry.field.example != null) 'say "${entry.field.example}"',
      ];
      if (parts.isNotEmpty) subtitle = parts.join('  ·  ');
    }

    final highlight = isNext && listening;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: EdgeInsets.only(bottom: m.spaceXs),
      padding: EdgeInsets.symmetric(horizontal: m.spaceMd, vertical: m.spaceSm),
      decoration: BoxDecoration(
        color: highlight ? palette.primaryContainer : palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          SizedBox(width: m.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(entry.field.label, style: context.texts.bodyMedium),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: context.texts.labelSmall
                        ?.copyWith(color: palette.onSurfaceMuted),
                  ),
              ],
            ),
          ),
          SizedBox(width: m.spaceSm),
          Text(
            trailing,
            style: context.texts.labelMedium?.copyWith(
              color: entry.status == FieldStatus.filled
                  ? palette.onSurface
                  : palette.onSurfaceMuted,
              fontWeight: entry.status == FieldStatus.filled
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when no speech model is installed — voice entry transcribes on device,
/// so it needs one.
class _NeedsModel extends StatelessWidget {
  const _NeedsModel({required this.metrics});

  final ThemeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(m.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.mic_off_outlined),
                SizedBox(width: m.spaceSm),
                Text('Voice entry', style: context.texts.titleMedium),
              ],
            ),
            SizedBox(height: m.spaceMd),
            Text(
              'Speaking vitals in needs a speech model on this device — it is '
              'what turns what you say into a value, all on device.',
              style: context.texts.bodyMedium,
            ),
            SizedBox(height: m.spaceLg),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.go(Routes.dictation);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Set up dictation'),
            ),
          ],
        ),
      ),
    );
  }
}
