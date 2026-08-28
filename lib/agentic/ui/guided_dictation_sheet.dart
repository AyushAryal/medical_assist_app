import 'dart:async';
import 'dart:convert';

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

/// How the clinician gives the values.
enum _Mode {
  /// Say each value — "BP 120 over 80, pulse 88". Deterministic parsing.
  dictate,

  /// Describe the obs freely — "looks unwell, pressure was 120 on 80, a bit
  /// tachy at 110, febrile" — and the on-device model infers the numbers.
  describe,
}

/// Hands-free vitals entry. Tap listen, speak, and pause — the recording stops
/// on its own, the values are transcribed on device and fill a live preview.
/// Everything is a proposal the clinician reviews and saves; nothing is trusted
/// blindly, so a value outside its plausible range is refused rather than
/// written. The routing, sanitising and model-output validation are unit-
/// tested; the audio runs on device.
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
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
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

  _Mode _mode = _Mode.dictate;
  bool _listening = false;
  bool _working = false;
  double _level = 0;
  bool _sawSpeech = false;
  String? _heard;
  Timer? _levelTimer;

  static const _silenceStop = Duration(milliseconds: 1400);

  @override
  void dispose() {
    _levelTimer?.cancel();
    super.dispose();
  }

  Future<void> _startListen() async {
    final started = await widget.bootstrap.dictation.start();
    if (!mounted || !started) return;
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
      // Auto-stop once the clinician has spoken and then paused — no button.
      if (_sawSpeech && level.silenceRun >= _silenceStop) {
        _stopAndProcess();
      }
    });
  }

  Future<void> _stopAndProcess() async {
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
      if (mounted) setState(() => _heard = result.text);

      if (_mode == _Mode.dictate) {
        _controller.applyTranscript(result.text);
      } else {
        await _describe(result.text);
      }
    } on Object {
      if (mounted) setState(() => _heard = 'Could not transcribe — try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _describe(String text) async {
    final engine = widget.bootstrap.assistEngine;
    if (engine == null) {
      setState(() => _heard =
          'Describe needs an on-device assistant model (Settings › On-device '
          'AI). Or switch to Dictate and say each value.');
      return;
    }
    final reply = await engine.extractValues(
      text,
      fields: widget.surface.fillable.map((f) => f.id).toList(),
    );
    final json = _asJson(reply);
    if (json != null) _controller.applyExtractionJson(json);
  }

  /// The model's reply may carry stray prose; take the first JSON object.
  Map<String, Object?>? _asJson(String? reply) {
    if (reply == null) return null;
    final start = reply.indexOf('{');
    final end = reply.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(reply.substring(start, end + 1));
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
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
            SizedBox(height: m.spaceSm),
            _modeToggle(context),
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
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: m.spaceMd),
            _listenArea(context),
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
        SizedBox(width: m.spaceSm),
        const AiBadge(label: 'AI', dense: true),
        const Spacer(),
        Text(
          '${_controller.filledCount} / ${_controller.total}',
          style: context.texts.labelMedium,
        ),
      ],
    );
  }

  Widget _modeToggle(BuildContext context) {
    return SegmentedButton<_Mode>(
      segments: const <ButtonSegment<_Mode>>[
        ButtonSegment<_Mode>(
          value: _Mode.dictate,
          label: Text('Dictate'),
          icon: Icon(Icons.spatial_audio_off, size: 18),
        ),
        ButtonSegment<_Mode>(
          value: _Mode.describe,
          label: Text('Describe'),
          icon: Icon(Icons.auto_awesome, size: 18),
        ),
      ],
      selected: <_Mode>{_mode},
      showSelectedIcon: false,
      onSelectionChanged: _listening || _working
          ? null
          : (s) => setState(() => _mode = s.first),
    );
  }

  Widget _listenArea(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    final hint = _mode == _Mode.dictate
        ? 'Say each value — "BP 120 over 80, pulse 88, temp 38.6". Say "skip".'
        : 'Describe the obs in your own words — the assistant reads the numbers.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The live audio plot while listening, so a working mic is obvious;
        // the hint or what was heard otherwise. The glow marks it as the AI
        // feature at work.
        AiGlowBorder(
          active: _listening || _working,
          borderRadius: BorderRadius.circular(m.radiusMd),
          child: Container(
            height: 64,
            padding: EdgeInsets.symmetric(horizontal: m.spaceMd),
            alignment: Alignment.center,
            child: _listening
                ? SiriWaveform(level: _level.clamp(0.05, 1.0), active: true)
                : Text(
                    _working
                        ? 'Reading what you said…'
                        : _heard == null
                            ? hint
                            : 'Heard: "$_heard"',
                    style: context.texts.labelMedium
                        ?.copyWith(color: palette.onSurfaceMuted),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ),
        SizedBox(height: m.spaceMd),
        FilledButton.icon(
          onPressed: _working
              ? null
              : (_listening ? _stopAndProcess : _startListen),
          icon: Icon(_listening ? Icons.stop : Icons.mic),
          label: Text(
            _working
                ? 'Working…'
                : _listening
                    ? 'Stop'
                    : (_controller.filledCount == 0 ? 'Listen' : 'Add more'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(_controller.complete ? 'Review & save' : 'Close'),
        ),
      ],
    );
  }
}

/// One field in the live preview, its status shown by icon, colour and value.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.entry, required this.isNext});

  final FieldEntry entry;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    final (IconData icon, Color color) = switch (entry.status) {
      FieldStatus.filled => (Icons.check_circle, palette.normal),
      FieldStatus.skipped => (Icons.remove_circle_outline, palette.onSurfaceMuted),
      FieldStatus.rejected => (Icons.error_outline, palette.caution),
      FieldStatus.pending => (
          isNext ? Icons.graphic_eq : Icons.circle_outlined,
          isNext ? palette.primary : palette.onSurfaceMuted,
        ),
    };

    final trailing = switch (entry.status) {
      FieldStatus.filled => entry.display ?? '',
      FieldStatus.skipped => 'skipped',
      FieldStatus.rejected => 'not caught — repeat',
      FieldStatus.pending => isNext ? 'listening…' : '',
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: EdgeInsets.only(bottom: m.spaceXs),
      padding: EdgeInsets.symmetric(horizontal: m.spaceMd, vertical: m.spaceSm),
      decoration: BoxDecoration(
        color: isNext ? palette.primaryContainer : palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
        border: isNext
            ? Border.all(color: palette.primary.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          SizedBox(width: m.spaceSm),
          Expanded(
            child: Text(entry.field.label, style: context.texts.bodyMedium),
          ),
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
