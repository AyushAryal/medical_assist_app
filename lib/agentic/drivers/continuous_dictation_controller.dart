import '../../core/agentic/agent_surface.dart';
import 'spoken_value.dart';
import 'surface_extraction.dart';

/// The state of one field as a continuous dictation progresses.
enum FieldStatus { pending, filled, skipped, rejected }

/// A field plus what has happened to it — the row the live preview renders.
class FieldEntry {
  FieldEntry(this.field);

  final AgentField field;
  FieldStatus status = FieldStatus.pending;

  /// The filled value as shown, e.g. `120/80 mmHg` or `88 bpm`. Null unless
  /// [status] is [FieldStatus.filled].
  String? display;
}

/// What one recognised phrase did — drives the spoken read-back and any
/// animation on the preview.
enum ContinuousOutcome {
  filled,
  skipped,
  cleared,
  rejected,
  unclear,
  stopped,
  nothingLeft,
}

/// The brain of hands-free, one-speech vitals entry.
///
/// The clinician talks — "BP one-twenty over eighty", "pulse eighty-eight",
/// "temp thirty-eight six", "skip glucose", "done" — without touching the
/// phone. Each VAD-segmented phrase is fed here as a transcript. This routes it
/// to the field the clinician named (falling back to the next pending field),
/// sanitises the value against the field's plausible bounds, and updates a live
/// per-field status the UI previews as it happens.
///
/// It only ever *proposes* into the fields (via the surface callbacks); the
/// clinician still reviews the filled form and saves. Pure Dart, unit-tested;
/// the audio and VAD that produce the transcripts live at the UI edge.
class ContinuousDictationController {
  ContinuousDictationController(
    AgentSurface surface, {
    this.parser = const SpokenValueParser(),
  }) : entries = <FieldEntry>[
          for (final field in surface.fillable) FieldEntry(field),
        ];

  final SpokenValueParser parser;
  final List<FieldEntry> entries;
  bool _stopped = false;

  int get total => entries.length;
  int get filledCount =>
      entries.where((e) => e.status == FieldStatus.filled).length;

  bool get complete =>
      _stopped || entries.every((e) => e.status != FieldStatus.pending);

  /// The next field still waiting — what the preview highlights as "up next".
  AgentField? get current {
    for (final entry in entries) {
      if (entry.status == FieldStatus.pending) return entry.field;
    }
    return null;
  }

  /// Splits a whole spoken transcript into per-field phrases, so a clinician
  /// can say the entire set in one breath — "BP one-twenty over eighty, pulse
  /// eighty-eight, temp thirty-eight six, skip glucose, done" — and each phrase
  /// is applied in turn. Boundaries are the field names and the control words;
  /// text before the first boundary (throat-clearing, "so the…") is dropped.
  static List<String> splitPhrases(String transcript, AgentSurface surface) {
    final text = transcript.toLowerCase();
    final markers = <({String text, bool isField})>[
      for (final field in surface.fillable) ...<({String text, bool isField})>[
        (text: field.label.toLowerCase(), isField: true),
        ...field.aliases.map((a) => (text: a.toLowerCase(), isField: true)),
      ],
      for (final w in _stopWords) (text: w, isField: false),
      for (final w in _skipWords) (text: w, isField: false),
      for (final w in _clearWords) (text: w, isField: false),
    ]..sort((a, b) => b.text.length.compareTo(a.text.length));

    // Longest markers claim their span first, so "pressure" cannot cut inside
    // "blood pressure".
    final claimed = <List<int>>[];
    final boundaries = <({int start, bool isField})>[];
    for (final marker in markers) {
      final pattern = marker.text.contains(' ')
          ? RegExp(RegExp.escape(marker.text))
          : RegExp(r'\b' + RegExp.escape(marker.text) + r'\b');
      for (final match in pattern.allMatches(text)) {
        final overlaps =
            claimed.any((r) => match.start < r[1] && match.end > r[0]);
        if (overlaps) continue;
        claimed.add(<int>[match.start, match.end]);
        boundaries.add((start: match.start, isField: marker.isField));
      }
    }
    if (boundaries.isEmpty) {
      final trimmed = transcript.trim();
      return trimmed.isEmpty ? const <String>[] : <String>[trimmed];
    }
    boundaries.sort((a, b) => a.start.compareTo(b.start));

    // A field name that directly follows a skip/clear word belongs to that
    // command — "skip glucose" is one phrase, not two.
    final cuts = <int>[];
    for (final boundary in boundaries) {
      if (boundary.isField && cuts.isNotEmpty) {
        final between = text.substring(cuts.last, boundary.start).trim();
        if (_skipWords.contains(between) || _clearWords.contains(between)) {
          continue;
        }
      }
      cuts.add(boundary.start);
    }

    final phrases = <String>[];
    for (var i = 0; i < cuts.length; i++) {
      final end = i + 1 < cuts.length ? cuts[i + 1] : text.length;
      final phrase = transcript.substring(cuts[i], end).trim();
      if (phrase.isNotEmpty) phrases.add(phrase);
    }
    return phrases;
  }

  /// Applies a whole transcript by splitting it into phrases and applying each.
  /// Returns true if anything was filled or skipped — i.e. the speech landed.
  bool applyTranscript(String transcript) {
    var landed = false;
    for (final phrase in splitPhrases(transcript, _surfaceOf())) {
      final outcome = apply(phrase);
      if (outcome == ContinuousOutcome.filled ||
          outcome == ContinuousOutcome.skipped) {
        landed = true;
      }
      if (outcome == ContinuousOutcome.stopped) break;
    }
    return landed;
  }

  AgentSurface _surfaceOf() =>
      AgentSurface(<AgentField>[for (final e in entries) e.field]);

  /// Applies a model's structured extraction (the *describe* driver) to the
  /// same preview: valid values fill their field, out-of-bounds or wrong-kind
  /// ones are flagged rejected, unknown keys ignored. Returns how many landed.
  int applyExtractionJson(Map<String, Object?> json) {
    final result = const SurfaceExtraction().apply(json, _surfaceOf());
    for (final entry in entries) {
      if (result.filled.contains(entry.field.id)) {
        entry.status = FieldStatus.filled;
        entry.display = result.displays[entry.field.id];
      } else if (result.rejected.contains(entry.field.id)) {
        entry.status = FieldStatus.rejected;
        entry.display = null;
      }
    }
    return result.filledCount;
  }

  ContinuousOutcome apply(String transcript) {
    if (_stopped) return ContinuousOutcome.stopped;
    final text = transcript.trim().toLowerCase();
    if (text.isEmpty) return ContinuousOutcome.unclear;

    if (_matchesAny(text, _stopWords)) {
      _stopped = true;
      return ContinuousOutcome.stopped;
    }

    // Which field is this about? A named one wins; otherwise the current one.
    final named = _resolveField(text);
    final field = named?.field ?? current;
    if (field == null) return ContinuousOutcome.nothingLeft;
    final entry = _entryFor(field)!;

    if (_matchesAny(text, _clearWords)) {
      entry.status = FieldStatus.pending;
      entry.display = null;
      return ContinuousOutcome.cleared;
    }
    if (_matchesAny(text, _skipWords)) {
      entry.status = FieldStatus.skipped;
      entry.display = null;
      return ContinuousOutcome.skipped;
    }

    // Strip the field name so "pulse eighty eight" parses "eighty eight".
    final residual = named == null ? text : text.replaceFirst(named.alias, ' ');
    return _fill(entry, parser.parse(residual));
  }

  ContinuousOutcome _fill(FieldEntry entry, Utterance utterance) {
    final field = entry.field;
    switch (utterance) {
      case NumberUtterance(:final value):
        if (field.kind == AgentFieldKind.pair) return ContinuousOutcome.unclear;
        if (!field.accepts(value)) {
          entry.status = FieldStatus.rejected;
          entry.display = null;
          return ContinuousOutcome.rejected;
        }
        field.proposeNumber?.call(value);
        return _accept(entry, _withUnit(field, _fmt(value)));
      case PairUtterance(:final first, :final second):
        if (field.kind != AgentFieldKind.pair) return ContinuousOutcome.unclear;
        if (!field.accepts(first) || !field.accepts(second)) {
          entry.status = FieldStatus.rejected;
          entry.display = null;
          return ContinuousOutcome.rejected;
        }
        field.proposePair?.call(first, second);
        return _accept(entry, _withUnit(field, '$first/$second'));
      case CommandUtterance():
      case UnclearUtterance():
        return ContinuousOutcome.unclear;
    }
  }

  ContinuousOutcome _accept(FieldEntry entry, String display) {
    entry.status = FieldStatus.filled;
    entry.display = display;
    return ContinuousOutcome.filled;
  }

  FieldEntry? _entryFor(AgentField field) {
    for (final entry in entries) {
      if (entry.field.id == field.id) return entry;
    }
    return null;
  }

  ({AgentField field, String alias})? _resolveField(String text) {
    ({AgentField field, String alias})? best;
    for (final entry in entries) {
      final alias = entry.field.matchAlias(text);
      if (alias != null &&
          (best == null || alias.length > best.alias.length)) {
        best = (field: entry.field, alias: alias);
      }
    }
    return best;
  }

  static String _withUnit(AgentField field, String value) =>
      field.unit == null ? value : '$value ${field.unit}';

  static String _fmt(num value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  static bool _matchesAny(String text, Set<String> words) {
    final tokens = text.split(RegExp(r'[^a-z]+')).toSet();
    return words.any(tokens.contains);
  }

  static const Set<String> _stopWords = <String>{
    'done', 'stop', 'finish', 'finished', 'end', 'complete',
  };
  static const Set<String> _skipWords = <String>{
    'skip', 'none', 'blank', 'leave',
  };
  static const Set<String> _clearWords = <String>{
    'redo', 'again', 'clear', 'wrong', 'scratch',
  };
}
