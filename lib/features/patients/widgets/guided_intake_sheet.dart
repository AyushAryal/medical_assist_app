import 'dart:async';

import 'package:flutter/material.dart';

import '../../../clinical/insights/note_intelligence.dart';
import '../../../core/app_bootstrap.dart';
import '../../../core/design/design.dart';

/// Guided voice intake: the same hands-free ceremony as vitals voice entry —
/// waveform, live checklist, no buttons between phrases — walked across the
/// record's list sections instead of numbers. "Penicillin, causes a rash" …
/// "diabetes and hypertension" … "metformin five hundred" … done.
///
/// Each phrase is transcribed on device and run through the deterministic
/// extractor for the section being asked about; what it recognises stages in
/// the checklist immediately. A phrase that yields nothing does not advance —
/// the sheet says what it heard and asks again or offers "skip", which is the
/// clarification loop. Nothing is filed here: the transcript and its
/// recognised entries return to Smart intake for the same review-then-Add
/// path as typed text.
class GuidedIntakeSheet extends StatefulWidget {
  const GuidedIntakeSheet({super.key, required this.bootstrap});

  final AppBootstrap bootstrap;

  /// Returns the raw transcript of everything said (per section), or null if
  /// cancelled.
  static Future<String?> show(BuildContext context, AppBootstrap bootstrap) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      builder: (_) => GuidedIntakeSheet(bootstrap: bootstrap),
    );
  }

  @override
  State<GuidedIntakeSheet> createState() => _GuidedIntakeSheetState();
}

class _Section {
  _Section(this.kind, this.title, this.example);

  final ExtractedTermKind kind;
  final String title;
  final String example;

  final List<String> heard = <String>[];
  final List<ExtractedTerm> found = <ExtractedTerm>[];
  bool skipped = false;
  bool done = false;
}

class _GuidedIntakeSheetState extends State<GuidedIntakeSheet> {
  final List<_Section> _sections = <_Section>[
    _Section(ExtractedTermKind.allergy, 'Allergies', 'allergic to penicillin'),
    _Section(
      ExtractedTermKind.problem,
      'Problems',
      'diabetes and hypertension',
    ),
    _Section(
      ExtractedTermKind.medication,
      'Medications',
      'metformin 500 mg twice daily',
    ),
  ];

  int _index = 0;
  bool _session = false;
  bool _listening = false;
  bool _working = false;
  bool _sawSpeech = false;
  double _level = 0;

  /// The clarification line: what was heard when nothing was recognised.
  String? _clarify;

  Timer? _levelTimer;
  DateTime? _phraseStartedAt;

  static const _silenceStop = Duration(milliseconds: 650);
  static const _maxPhrase = Duration(seconds: 6);

  _Section? get _current =>
      _index < _sections.length ? _sections[_index] : null;
  bool get _complete => _index >= _sections.length;

  @override
  void dispose() {
    _levelTimer?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() {
      _session = true;
      _clarify = null;
    });
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
    _phraseStartedAt = null;
    _levelTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted || !_listening) return;
      final level = widget.bootstrap.dictation.level;
      if (level.isSpeaking && !_sawSpeech) {
        _sawSpeech = true;
        _phraseStartedAt = DateTime.now();
      }
      setState(() => _level = level.current);
      final ranLong =
          _phraseStartedAt != null &&
          DateTime.now().difference(_phraseStartedAt!) >= _maxPhrase;
      if (_sawSpeech && (level.silenceRun >= _silenceStop || ranLong)) {
        _capturePhrase();
      }
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
      _apply(result.text.trim());
    } on Object {
      if (mounted) setState(() => _clarify = 'Did not catch that — again?');
    } finally {
      if (mounted) {
        setState(() => _working = false);
        if (_session && !_complete) {
          _beginListen();
        } else {
          setState(() => _session = false);
        }
      }
    }
  }

  void _apply(String text) {
    final section = _current;
    if (section == null || text.isEmpty) return;
    final lower = text.toLowerCase();

    if (RegExp(r'\b(done|finish|finished|stop)\b').hasMatch(lower)) {
      _session = false;
      setState(() => _index = _sections.length);
      return;
    }
    if (RegExp(r'\b(skip|none|no known|nothing)\b').hasMatch(lower)) {
      setState(() {
        section.skipped = true;
        section.done = true;
        _clarify = null;
        _index++;
      });
      return;
    }

    final found = NoteIntelligence.extract(
      text,
    ).where((term) => term.kind == section.kind).toList();
    if (found.isEmpty) {
      // Clarification, not silent failure: say what was heard, stay on the
      // same section, and remind the way out.
      setState(
        () => _clarify =
            'Heard "$text" — no ${section.title.toLowerCase()} recognised. '
            'Try again, or say "skip".',
      );
      return;
    }
    setState(() {
      section.heard.add(text);
      section.found.addAll(found);
      section.done = true;
      _clarify = null;
      _index++;
    });
  }

  void _finish() {
    final transcript = <String>[
      for (final section in _sections)
        if (section.heard.isNotEmpty)
          '${section.title}: ${section.heard.join('. ')}',
    ].join('\n');
    Navigator.of(context).pop(transcript.isEmpty ? null : transcript);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final foundCount = _sections.fold<int>(0, (sum, s) => sum + s.found.length);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const AiSparkleIcon(size: 20),
                SizedBox(width: m.spaceSm),
                Text('Voice intake', style: context.texts.titleMedium),
                SizedBox(width: m.spaceSm),
                const AiBadge(label: 'AI', dense: true),
                const Spacer(),
                Text('$foundCount found', style: context.texts.labelMedium),
              ],
            ),
            SizedBox(height: m.spaceMd),
            for (final (i, section) in _sections.indexed)
              _SectionRow(
                section: section,
                isNext: i == _index,
                listening: _session,
              ),
            SizedBox(height: m.spaceMd),
            AiGlowBorder(
              active: _session || _working,
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
                            : _clarify ??
                                  (_complete
                                      ? 'Done — review below, then add.'
                                      : 'Tap start, then answer each section '
                                            'with a pause between — e.g. '
                                            '"${_current?.example}", or "skip".'),
                        style: context.texts.labelMedium?.copyWith(
                          color: palette.onSurfaceMuted,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),
            SizedBox(height: m.spaceMd),
            if (!_session && !_complete)
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.mic),
                label: Text(foundCount == 0 ? 'Start' : 'Continue'),
              )
            else if (_session)
              OutlinedButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            if (foundCount > 0 || _complete) ...<Widget>[
              SizedBox(height: m.spaceSm),
              FilledButton.tonalIcon(
                onPressed: _finish,
                icon: const Icon(Icons.playlist_add_check, size: 18),
                label: Text('Use what was heard ($foundCount)'),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One section in the live checklist — mirrors the vitals sheet's rows.
class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.isNext,
    required this.listening,
  });

  final _Section section;
  final bool isNext;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    final (IconData icon, Color color) = section.done
        ? section.skipped
              ? (Icons.remove_circle_outline, palette.onSurfaceMuted)
              : (Icons.check_circle, palette.normal)
        : (
            isNext && listening ? Icons.graphic_eq : Icons.circle_outlined,
            isNext && listening ? palette.primary : palette.onSurfaceMuted,
          );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          SizedBox(width: m.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(section.title, style: context.texts.labelLarge),
                if (section.found.isNotEmpty)
                  Text(
                    section.found.map((t) => t.text).join(', '),
                    style: context.texts.bodySmall?.copyWith(
                      color: palette.onSurfaceMuted,
                    ),
                  )
                else if (section.skipped)
                  Text(
                    'skipped',
                    style: context.texts.bodySmall?.copyWith(
                      color: palette.onSurfaceMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
