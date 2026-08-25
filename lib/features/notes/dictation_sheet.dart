import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../../data/services/dictation_recorder.dart';
import '../../data/services/transcription/transcription_engine.dart';
import '../attachments/inline_audio_player.dart';

/// What the clinician takes away from a dictation.
class DictationOutcome {
  const DictationOutcome({
    required this.audio,
    this.transcript,
  });

  /// The trimmed recording, to be attached to the note as evidence.
  final DictationCapture audio;

  /// The text, if a speech model is installed and the clinician kept it.
  final String? transcript;

  bool get hasTranscript => transcript?.trim().isNotEmpty ?? false;
}

/// Record, trim, transcribe, review — in that order, on one screen.
///
/// The order is the design. Transcription is offered *after* the recording
/// exists and is never a precondition for it, so a failed or unavailable
/// transcriber costs the clinician nothing: the dictation is already captured
/// and attached. And the transcript is shown for review before it can reach the
/// note, because Whisper misreads drug names and doses confidently, and a
/// wrong dose written into a record by a machine is not a transcription error,
/// it is a prescribing error.
class DictationSheet extends StatefulWidget {
  const DictationSheet({super.key, required this.sectionLabel});

  final String sectionLabel;

  static Future<DictationOutcome?> show(
    BuildContext context, {
    required String sectionLabel,
  }) {
    return showModalBottomSheet<DictationOutcome>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => DictationSheet(sectionLabel: sectionLabel),
    );
  }

  @override
  State<DictationSheet> createState() => _DictationSheetState();
}

enum _Stage { ready, recording, processing, review }

class _DictationSheetState extends State<DictationSheet> {
  _Stage _stage = _Stage.ready;
  DictationCapture? _capture;
  String? _error;
  bool _busy = false;

  /// This recording's own answer to "keep the untrimmed audio?".
  ///
  /// Seeded from the Settings default and overridable here, because the
  /// decision is per-dictation in practice: a routine follow-up needs nothing
  /// but the transcript, and the one consultation someone expects to be
  /// disputed needs exactly what the microphone heard. Making that a setting
  /// you have to leave the note to change means it is set once and never
  /// revisited.
  bool? _keepOriginalOverride;

  /// The stretch currently marked for removal, as fractions.
  (double, double)? _selection;

  /// Previous versions, so a cut can be taken back.
  ///
  /// Cutting audio is destructive and the mistake is invisible once made — the
  /// part you removed is simply not there any more, and there is nothing on
  /// screen to tell you what it was. Undo is not a nicety here.
  final List<DictationCapture> _history = <DictationCapture>[];

  bool get _keepOriginal =>
      _keepOriginalOverride ??
      context.read<AppBootstrap>().dictation.keepOriginal;

  bool _transcribing = false;
  TranscriptionResult? _transcript;
  final TextEditingController _edited = TextEditingController();

  DictationRecorder get _recorder => context.read<AppBootstrap>().dictation;

  @override
  void dispose() {
    _edited.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    // Applied for this recording only; the stored default is untouched.
    _recorder.keepOriginal = _keepOriginal;
    final started = await _recorder.start();
    if (!mounted) return;
    if (!started) {
      setState(
        () => _error = 'The microphone is not available. Check that this app '
            'has permission to use it.',
      );
      return;
    }
    setState(() => _stage = _Stage.recording);
  }

  Future<void> _stop() async {
    setState(() => _stage = _Stage.processing);
    final capture = await _recorder.stop();
    if (!mounted) return;

    if (capture == null) {
      setState(() {
        _stage = _Stage.ready;
        _error = 'Nothing was recorded — the microphone picked up only '
            'silence. Check that it is not covered, and try again.';
      });
      return;
    }

    setState(() {
      _capture = capture;
      _stage = _Stage.review;
    });

    // Start transcribing straight away: the clinician is already waiting, and
    // reviewing the text is the slow part.
    final bootstrap = context.read<AppBootstrap>();
    if (bootstrap.canTranscribe) unawaited(_transcribe());
  }

  /// Removes the marked stretch. Can be repeated as many times as needed.
  Future<void> _cutSelection() async {
    final capture = _capture;
    final selection = _selection;
    if (capture == null || selection == null || _busy) return;
    if (selection.$2 - selection.$1 < 0.005) return;

    setState(() => _busy = true);
    final cut = await _recorder.removeRange(
      capture,
      startFraction: selection.$1,
      endFraction: selection.$2,
    );
    if (!mounted) return;
    setState(() {
      _history.add(capture);
      _capture = cut;
      _selection = null;
      _busy = false;
      // The transcript belonged to the longer audio, so it is no longer the
      // transcript of this recording.
      _transcript = null;
      _edited.clear();
    });
  }

  void _undoCut() {
    if (_history.isEmpty) return;
    setState(() {
      _capture = _history.removeLast();
      _selection = null;
      _transcript = null;
      _edited.clear();
    });
  }

  Future<void> _transcribe() async {
    final capture = _capture;
    if (capture == null || _transcribing) return;

    setState(() {
      _transcribing = true;
      _error = null;
    });

    final engine = context.read<AppBootstrap>().transcription;
    try {
      final availability = await engine.availability();
      if (!availability.isReady) {
        if (!mounted) return;
        setState(() {
          _transcribing = false;
          _error = availability.reason;
        });
        return;
      }

      final result = await engine.transcribe(capture.file);
      if (!mounted) return;
      setState(() {
        _transcript = result;
        _edited.text = result.text;
        _transcribing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _transcribing = false;
        _error = 'Transcription failed: $error\n\nThe recording is safe and '
            'can still be attached.';
      });
    }
  }

  /// Throws away what has been said so far and starts recording again.
  Future<void> _retake() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _recorder.cancel();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _capture = null;
      _transcript = null;
      _edited.clear();
      _error = null;
    });
    await _start();
  }

  Future<void> _cancel() async {
    await _recorder.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  void _accept({required bool withTranscript}) {
    final capture = _capture;
    if (capture == null) return;
    Navigator.of(context).pop(
      DictationOutcome(
        audio: capture,
        transcript: withTranscript ? _edited.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          maxWidth: m.contentMaxWidth,
        ),
        child: Padding(
          padding: EdgeInsets.all(m.spaceLg),
          child: switch (_stage) {
            _Stage.ready => _readyView(context),
            _Stage.recording => _recordingView(context),
            _Stage.processing => _processingView(context),
            _Stage.review => _reviewView(context),
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String title, String subtitle) {
    final m = context.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(title, style: context.texts.titleLarge)),
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close),
              onPressed: _cancel,
            ),
          ],
        ),
        Text(subtitle, style: context.texts.bodySmall),
        SizedBox(height: m.spaceLg),
      ],
    );
  }

  Widget _readyView(BuildContext context) {
    final m = context.metrics;
    final bootstrap = context.watch<AppBootstrap>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(
          context,
          'Dictate — ${widget.sectionLabel}',
          'Silence is removed automatically. The recording is attached to the '
              'note either way.',
        ),
        if (_error != null) ...<Widget>[
          _ErrorNote(message: _error!),
          SizedBox(height: m.spaceMd),
        ],
        Row(
          children: <Widget>[
            Icon(
              bootstrap.canTranscribe
                  ? Icons.text_fields
                  : Icons.text_fields_outlined,
              size: 17,
              color: context.palette.onSurfaceMuted,
            ),
            SizedBox(width: m.spaceSm),
            Expanded(
              child: Text(
                bootstrap.canTranscribe
                    ? 'Will be transcribed on this device by '
                        '${bootstrap.transcription.name}. Nothing is sent '
                        'anywhere.'
                    : 'No speech model installed — the recording will be '
                        'attached as audio. Settings › Dictation to add one.',
                style: context.texts.labelSmall,
              ),
            ),
          ],
        ),
        SizedBox(height: m.spaceLg),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.mic),
          label: const Text('Start recording'),
        ),
      ],
    );
  }

  Widget _recordingView(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return ListenableBuilder(
      listenable: _recorder,
      builder: (context, _) {
        final level = _recorder.level;
        final seconds = level.elapsed.inSeconds;
        final droppingSilence = level.silenceRun.inSeconds >= 2;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(
              context,
              'Recording',
              'Speak normally. Pauses are removed when you stop.',
            ),
            Center(
              child: Text(
                '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                style: context.texts.displaySmall?.copyWith(
                  color: palette.critical,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            SizedBox(height: m.spaceMd),
            AiAuroraBackground(
              active: level.isSpeaking,
              child: SiriWaveform(
                level: level.current,
                active: true,
              ),
            ),
            SizedBox(height: m.spaceSm),
            Center(
              child: Text(
                droppingSilence
                    ? 'Silence — this pause will be trimmed'
                    : level.isSpeaking
                        ? 'Picking up your voice'
                        : 'Listening',
                style: context.texts.labelSmall?.copyWith(
                  color: droppingSilence
                      ? palette.onSurfaceMuted
                      : level.isSpeaking
                          ? palette.normal
                          : palette.onSurfaceMuted,
                ),
              ),
            ),
            SizedBox(height: m.spaceLg),
            FilledButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
            SizedBox(height: m.spaceSm),
            Row(
              children: <Widget>[
                Expanded(
                  // Start again without leaving the sheet. Someone who
                  // fumbles the first sentence otherwise has to discard,
                  // reopen and re-find the section — three taps to undo a
                  // stumble, which is enough friction that people instead
                  // keep a bad recording and fix it in text later.
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _retake,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Start over'),
                  ),
                ),
                SizedBox(width: m.spaceSm),
                Expanded(
                  child: TextButton(
                    onPressed: _cancel,
                    child: const Text('Discard'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _processingView(BuildContext context) {
    final m = context.metrics;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(height: m.spaceXl),
        const CircularProgressIndicator(),
        SizedBox(height: m.spaceLg),
        Text('Removing silence…', style: context.texts.bodyMedium),
        SizedBox(height: m.spaceXl),
      ],
    );
  }

  Widget _reviewView(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final capture = _capture!;
    final bootstrap = context.watch<AppBootstrap>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(
          context,
          'Review',
          'Nothing is added to the note until you choose below.',
        ),
        Row(
          children: <Widget>[
            Icon(Icons.content_cut, size: 16, color: palette.normal),
            SizedBox(width: m.spaceSm),
            Expanded(
              child: Text(
                capture.savingSummary,
                style: context.texts.labelMedium,
              ),
            ),
            InfoDot(
              explanation: _trimExplanation(capture),
            ),
          ],
        ),
        SizedBox(height: m.spaceMd),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Listen before deciding anything. The previous flow asked for
                // every choice up front and then never let the clinician hear
                // what they had actually captured.
                InlineAudioPlayer(
                  key: ValueKey<String>(capture.file.path),
                  filePath: capture.file.path,
                  label: 'Trimmed recording',
                  durationMs: capture.duration.inMilliseconds,
                ),
                SizedBox(height: m.spaceMd),
                _TrimEditor(
                  capture: capture,
                  selection: _selection,
                  onSelect: (start, end) =>
                      setState(() => _selection = (start, end)),
                  onCut: _cutSelection,
                  onUndo: _history.isEmpty ? null : _undoCut,
                  busy: _busy,
                ),
                SizedBox(height: m.spaceMd),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _keepOriginal,
                  onChanged: (value) =>
                      setState(() => _keepOriginalOverride = value),
                  title: Text(
                    'Also keep the untrimmed original',
                    style: context.texts.labelMedium,
                  ),
                  subtitle: Text(
                    _keepOriginal
                        ? 'Both files attach to the note. Roughly doubles the '
                            'size.'
                        : 'Only what you hear above is kept.',
                    style: context.texts.labelSmall,
                  ),
                ),
                SizedBox(height: m.spaceMd),
                if (_error != null) ...<Widget>[
                  _ErrorNote(message: _error!),
                  SizedBox(height: m.spaceMd),
                ],
                if (_transcribing)
                  AiGlowBorder(
                    active: true,
                    child: AiAuroraBackground(
                      child: Padding(
                      padding: EdgeInsets.all(m.spaceLg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const AiSparkleIcon(size: 18),
                              SizedBox(width: m.spaceSm),
                              Expanded(
                                child: Text(
                                  'Listening back on this device — '
                                  '${capture.duration.inSeconds}s of speech',
                                  style: context.texts.labelLarge,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: m.spaceMd),
                          // Placeholder lines rather than a spinner: they
                          // preview the shape of what is coming, which is the
                          // honest signal when this takes longer than the
                          // recording did.
                          const AiTextPlaceholder(lines: 4),
                          SizedBox(height: m.spaceXs),
                          Text(
                            'Nothing leaves this device.',
                            style: context.texts.labelSmall,
                          ),
                        ],
                      ),
                      ),
                    ),
                  )
                else if (_transcript != null)
                  _TranscriptEditor(
                    controller: _edited,
                    result: _transcript!,
                  )
                else if (!bootstrap.canTranscribe)
                  const EmptyState(
                    icon: Icons.hearing_disabled_outlined,
                    title: 'No speech model installed',
                    message: 'The recording will be attached as audio. Add a '
                        'model in Settings › Dictation to get text as well.',
                    compact: true,
                  )
                else if (_error == null)
                  Padding(
                    padding: EdgeInsets.only(bottom: m.spaceMd),
                    child: OutlinedButton.icon(
                      onPressed: _transcribe,
                      icon: const Icon(Icons.text_fields),
                      label: const Text('Transcribe'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: m.spaceLg),
        if (_transcript != null)
          FilledButton.icon(
            onPressed: () => _accept(withTranscript: true),
            icon: const Icon(Icons.check),
            label: Text('Insert text into ${widget.sectionLabel}'),
          ),
        SizedBox(height: m.spaceSm),
        OutlinedButton.icon(
          onPressed: () => _accept(withTranscript: false),
          icon: const Icon(Icons.graphic_eq),
          label: const Text('Attach audio only'),
        ),
        SizedBox(height: m.spaceSm),
        Row(
          children: <Widget>[
            Expanded(
              child: TextButton.icon(
                onPressed: _retake,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Record again'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: _cancel,
                child: const Text('Discard'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  MetricExplanation _trimExplanation(DictationCapture capture) {
    return MetricExplanation(
      title: 'Silence removal',
      summary: 'The parts of the recording where nobody was speaking have been '
          'cut out, so the file is smaller and playing it back does not mean '
          'sitting through the pauses.',
      method: const <String>[
        'The recording is split into 20-millisecond frames and the loudness of '
            'each is measured.',
        'The quietest tenth of the recording is taken as the level of the room '
            'itself.',
        'A frame counts as speech when it is at least 8 decibels above that.',
        'Speech must hold for 60 milliseconds before it counts, so a dropped '
            'pen or a door does not.',
        'A quarter of a second before each phrase and just over a third of a '
            'second after it are kept, so no word is clipped at either end.',
      ],
      derivation: <ExplainRow>[
        ExplainRow(
          label: 'You recorded',
          value: '${capture.originalDuration.inSeconds}s',
        ),
        ExplainRow(
          label: 'Speech kept',
          value: '${capture.duration.inSeconds}s',
        ),
        ExplainRow(
          label: 'File size',
          value: '${(capture.storedBytes / 1024).round()} KB',
          note: 'from ${(capture.untrimmedBytes / 1024).round()} KB untrimmed',
        ),
      ],
      confidence: ExplainConfidence.measured,
      source: 'Energy-based voice activity detection — this app',
      caveat: 'It is deliberately biased toward keeping audio: it would rather '
          'leave a second of room noise in than cut off the start of a word. A '
          'very quiet voice in a very loud room may keep more than expected.',
    );
  }
}

class _TranscriptEditor extends StatelessWidget {
  const _TranscriptEditor({required this.controller, required this.result});

  final TextEditingController controller;
  final TranscriptionResult result;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const AiBadge(animate: true),
            SizedBox(width: m.spaceSm),
            Expanded(
              child: Text(
                'Transcribed on this device',
                style: context.texts.labelSmall,
              ),
            ),
          ],
        ),
        SizedBox(height: m.spaceSm),
        Container(
          padding: EdgeInsets.all(m.spaceMd),
          decoration: BoxDecoration(
            color: palette.caution.withValues(
              alpha: context.isDark ? 0.14 : 0.09,
            ),
            borderRadius: BorderRadius.circular(m.radiusSm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline, size: 17, color: palette.caution),
              SizedBox(width: m.spaceSm),
              Expanded(
                child: Text(
                  'Machine transcript — read it before you insert it. Drug '
                  'names, doses and numbers are where it goes wrong, and it '
                  'gets them wrong confidently.',
                  style: context.texts.bodySmall,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: m.spaceMd),
        TextField(
          controller: controller,
          maxLines: null,
          minLines: 4,
          style: context.texts.bodyMedium,
          decoration: const InputDecoration(
            labelText: 'Transcript — edit freely',
            alignLabelWithHint: true,
          ),
        ),
        SizedBox(height: m.spaceSm),
        Text(
          '${result.engineName} · ${result.processingTime.inSeconds}s to '
          'transcribe ${result.audioDuration.inSeconds}s of speech',
          style: context.texts.labelSmall,
        ),
      ],
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.all(m.spaceMd),
      decoration: BoxDecoration(
        color: palette.criticalSubtle,
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_outlined, size: 17, color: palette.critical),
          SizedBox(width: m.spaceSm),
          Expanded(child: Text(message, style: context.texts.bodySmall)),
        ],
      ),
    );
  }
}

/// Cut anything out of a finished recording, as many times as needed.
///
/// The first version offered two handles for the start and the end, which
/// covers the throat-clear and the trailing question — and misses what
/// actually happens most in a consultation room. Someone interrupts, a phone
/// rings, the clinician stops to think. Those are in the *middle*, they are
/// obvious on a waveform, and no detector should be deciding about them.
///
/// Drag across the shape to mark a stretch, remove it, repeat. Every cut is
/// undoable, which is not a nicety: removed audio leaves nothing on screen to
/// say what it was, so a mistake is invisible the moment it is made.
class _TrimEditor extends StatelessWidget {
  const _TrimEditor({
    required this.capture,
    required this.selection,
    required this.onSelect,
    required this.onCut,
    required this.onUndo,
    required this.busy,
  });

  final DictationCapture capture;
  final (double, double)? selection;
  final void Function(double start, double end) onSelect;
  final VoidCallback onCut;
  final VoidCallback? onUndo;
  final bool busy;

  static String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final marked = selection != null && selection!.$2 - selection!.$1 > 0.005;
    final markedFor = Duration(
      milliseconds: marked
          ? (capture.duration.inMilliseconds *
                  (selection!.$2 - selection!.$1))
              .round()
          : 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.content_cut, size: 15, color: palette.onSurfaceMuted),
            SizedBox(width: m.spaceSm),
            Expanded(
              child: Text('Cut anything out', style: context.texts.labelMedium),
            ),
            if (onUndo != null)
              TextButton.icon(
                onPressed: busy ? null : onUndo,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Undo'),
              ),
          ],
        ),
        SizedBox(height: m.spaceXs),
        PlaybackWaveform(
          progress: 0,
          playing: false,
          seed: capture.file.path,
          height: 52,
          selection: selection,
          onSelect: busy ? null : onSelect,
        ),
        SizedBox(height: m.spaceXs),
        if (marked)
          FilledButton.tonalIcon(
            onPressed: busy ? null : onCut,
            icon: const Icon(Icons.content_cut, size: 16),
            label: Text('Remove ${_clock(markedFor)}'),
          )
        else
          Text(
            'Drag across the shape to mark a stretch, then remove it. Repeat '
            'as often as you need.',
            style: context.texts.labelSmall,
          ),
      ],
    );
  }
}
