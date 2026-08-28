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

/// Hands-free vitals entry: the clinician taps listen once and says the whole
/// set — "BP one-twenty over eighty, pulse eighty-eight, temp thirty-eight six,
/// skip glucose, done" — while a live preview fills each field in, marks what
/// was skipped, and shows what is still pending. Every value is sanitised and
/// only *proposed* into the form; the clinician reviews and saves.
///
/// The audio + on-device transcription run at this edge; the routing,
/// sanitising and status machine ([ContinuousDictationController]) are unit-
/// tested. Live word-by-word streaming is a later on-device refinement — today
/// the preview updates each time a phrase (or the whole set) is transcribed.
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

  bool _listening = false;
  bool _working = false;
  String? _heard;

  Future<void> _toggleListen() async {
    final bootstrap = widget.bootstrap;
    if (!_listening) {
      final started = await bootstrap.dictation.start();
      if (mounted) setState(() => _listening = started);
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
      _controller.applyTranscript(result.text);
      if (mounted) setState(() => _heard = result.text);
    } on Object {
      if (mounted) {
        setState(() => _heard = 'Could not transcribe — try again.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
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
                        isNext: entry.field.id == _controller.current?.id,
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
        Expanded(
          child: Text('Guided dictation', style: context.texts.titleMedium),
        ),
        Text(
          '${_controller.filledCount} / ${_controller.total}',
          style: context.texts.labelMedium,
        ),
      ],
    );
  }

  Widget _listenArea(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 40,
          child: _listening
              ? const SiriWaveform(level: 0.7, active: true)
              : Center(
                  child: Text(
                    _heard == null
                        ? 'Say it all in one go — "BP 120 over 80, pulse 88, '
                            'temp 38.6, skip glucose, done".'
                        : 'Heard: "$_heard"',
                    style: context.texts.labelSmall
                        ?.copyWith(color: palette.onSurfaceMuted),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
        ),
        SizedBox(height: m.spaceSm),
        FilledButton.icon(
          onPressed: _working ? null : _toggleListen,
          icon: Icon(_listening ? Icons.stop : Icons.mic),
          label: Text(
            _working
                ? 'Transcribing…'
                : _listening
                    ? 'Stop'
                    : 'Listen',
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(
            _controller.complete ? 'Review & save' : 'Done',
          ),
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
          isNext ? Icons.mic_none_outlined : Icons.circle_outlined,
          isNext ? palette.primary : palette.onSurfaceMuted,
        ),
    };

    final trailing = switch (entry.status) {
      FieldStatus.filled => entry.display ?? '',
      FieldStatus.skipped => 'skipped',
      FieldStatus.rejected => 'not caught — repeat',
      FieldStatus.pending => isNext ? 'say this' : '',
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
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

/// Shown when no speech model is installed — guided dictation transcribes on
/// device, so it needs one.
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
                Text('Guided dictation', style: context.texts.titleMedium),
              ],
            ),
            SizedBox(height: m.spaceMd),
            Text(
              'Dictating vitals needs a speech model on this device — it is '
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
