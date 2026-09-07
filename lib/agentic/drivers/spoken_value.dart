/// Interpreting what a clinician says during guided vitals dictation.
///
/// This is the safety-critical core of the guided-dictation feature: a value
/// it reads wrong becomes a wrong number in a record. It is therefore
/// deliberately conservative — it returns [UnclearUtterance] rather than guess
/// whenever the utterance is not an unambiguous number, pair or command. A
/// declined utterance costs the clinician a repeat; a wrongly-confident one
/// costs a misread vital, which is far worse. Nothing here reaches a record on
/// its own: the value it yields is always a proposal the clinician confirms.
///
/// Pure Dart, no Flutter imports, so every band and edge case is unit-tested.
library;

/// A control word spoken instead of a value.
enum DictationCommand { next, skip, redo, back, stop }

/// The interpretation of one spoken utterance.
sealed class Utterance {
  const Utterance();
}

/// A single numeric reading — a pulse of 72, a temperature of 38.6.
class NumberUtterance extends Utterance {
  const NumberUtterance(this.value);
  final num value;

  @override
  bool operator ==(Object other) =>
      other is NumberUtterance && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => 'NumberUtterance($value)';
}

/// A pair spoken as "X over Y" — blood pressure, systolic then diastolic.
class PairUtterance extends Utterance {
  const PairUtterance(this.first, this.second);
  final int first;
  final int second;

  @override
  bool operator ==(Object other) =>
      other is PairUtterance && other.first == first && other.second == second;
  @override
  int get hashCode => Object.hash(first, second);
  @override
  String toString() => 'PairUtterance($first/$second)';
}

/// A control word — advance, skip, redo, go back, stop.
class CommandUtterance extends Utterance {
  const CommandUtterance(this.command);
  final DictationCommand command;

  @override
  bool operator ==(Object other) =>
      other is CommandUtterance && other.command == command;
  @override
  int get hashCode => command.hashCode;
  @override
  String toString() => 'CommandUtterance($command)';
}

/// Nothing confidently understood — the flow re-asks rather than guessing.
class UnclearUtterance extends Utterance {
  const UnclearUtterance(this.heard);
  final String heard;

  @override
  bool operator ==(Object other) =>
      other is UnclearUtterance && other.heard == heard;
  @override
  int get hashCode => heard.hashCode;
  @override
  String toString() => 'UnclearUtterance("$heard")';
}

class SpokenValueParser {
  const SpokenValueParser();

  /// Phrases that map onto each command. Matched as whole words so a value is
  /// never mistaken for a command (or vice versa).
  static const Map<DictationCommand, List<String>> _commandWords =
      <DictationCommand, List<String>>{
    DictationCommand.next: <String>['next', 'ok', 'okay', 'confirm', 'yes'],
    DictationCommand.skip: <String>['skip', 'none', 'blank', 'no value'],
    DictationCommand.redo: <String>[
      'redo',
      'again',
      'repeat',
      'scratch that',
      'clear',
      'wrong',
    ],
    DictationCommand.back: <String>['back', 'previous', 'go back'],
    DictationCommand.stop: <String>['stop', 'done', 'finish', 'finished', 'end'],
  };

  static final Map<String, int> _words = <String, int>{
    'zero': 0, 'oh': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11,
    'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
    'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60,
    'seventy': 70, 'eighty': 80, 'ninety': 90, 'hundred': 100,
  };

  Utterance parse(String transcript) {
    final text = transcript.trim().toLowerCase();
    if (text.isEmpty) return const UnclearUtterance('');

    // Commands win over numbers: "next" is never read as a stray value, and a
    // command word only counts when it, not a number, is what was said.
    final command = _command(text);
    if (command != null && !_hasNumber(text)) {
      return CommandUtterance(command);
    }

    final pair = _pair(text);
    if (pair != null) return pair;

    final number = _number(text);
    if (number != null) return NumberUtterance(number);

    if (command != null) return CommandUtterance(command);
    return UnclearUtterance(transcript.trim());
  }

  DictationCommand? _command(String text) {
    final words = text.split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty);
    final wordSet = words.toSet();
    for (final entry in _commandWords.entries) {
      for (final phrase in entry.value) {
        if (phrase.contains(' ')) {
          if (text.contains(phrase)) return entry.key;
        } else if (wordSet.contains(phrase)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  bool _hasNumber(String text) =>
      RegExp(r'\d').hasMatch(text) ||
      text.split(RegExp(r'[^a-z]+')).any(_words.containsKey);

  PairUtterance? _pair(String text) {
    final match = RegExp(
      r'(\d{1,3})\s*(?:over|on|/|\\|by)\s*(\d{1,3})',
    ).firstMatch(text);
    if (match == null) return null;
    final first = int.parse(match.group(1)!);
    final second = int.parse(match.group(2)!);
    return PairUtterance(first, second);
  }

  num? _number(String text) {
    // Prefer explicit digits, the form Whisper produces most of the time.
    final digits = RegExp(r'\d+(?:\.\d+)?').allMatches(text).toList();
    if (digits.length == 1) {
      return num.tryParse(digits.first.group(0)!);
    }
    // Two or more bare numbers with no "over" is ambiguous — decline.
    if (digits.length > 1) return null;

    // No digits: try a modest spoken-number reading (e.g. "ninety eight",
    // "one twenty", "thirty eight point six").
    return _spokenNumber(text);
  }

  num? _spokenNumber(String text) {
    final parts = text.split(RegExp(r'[^a-z.]+')).where((w) => w.isNotEmpty);
    final tokens = <String>[];
    for (final part in parts) {
      if (part == 'point' || _words.containsKey(part)) tokens.add(part);
    }
    if (tokens.isEmpty) return null;

    final pointIndex = tokens.indexOf('point');
    final whole = pointIndex == -1 ? tokens : tokens.sublist(0, pointIndex);
    final frac = pointIndex == -1
        ? const <String>[]
        : tokens.sublist(pointIndex + 1);

    final wholeValue = _composeWhole(whole);
    if (wholeValue == null) return null;
    if (frac.isEmpty) return wholeValue;

    // Decimal digits are read one at a time: "point six" -> .6, "point two
    // five" -> .25. Any non-single-digit word makes it ambiguous.
    final buffer = StringBuffer();
    for (final word in frac) {
      final digit = _words[word];
      if (digit == null || digit > 9) return null;
      buffer.write(digit);
    }
    return num.tryParse('$wholeValue.$buffer');
  }

  /// Composes the integer part from number words, conservatively. Handles a
  /// lone number ("seventy" -> 70), "ninety eight" (98) and the colloquial
  /// "one twenty" (120). Everything else — a bare "hundred", three or more
  /// number words, any combination it cannot place unambiguously — is
  /// declined, because a confident wrong number is worse than a repeat.
  int? _composeWhole(List<String> words) {
    if (words.isEmpty) return null;
    final values = <int>[];
    for (final word in words) {
      final value = _words[word];
      if (value == null) return null;
      values.add(value);
    }
    if (values.length == 1) {
      // "hundred" and "oh" alone are ambiguous vocalisations, not readings.
      if (words.first == 'hundred' || words.first == 'oh') return null;
      return values.first;
    }
    if (values.length == 2) {
      final a = values[0];
      final b = values[1];
      // "ninety eight" -> 90 + 8.
      if (a >= 20 && a % 10 == 0 && b >= 1 && b <= 9) return a + b;
      // "one twenty" -> 1*100 + 20, the way a BP is said aloud.
      if (a >= 1 && a <= 9 && b >= 20 && b % 10 == 0) return a * 100 + b;
      return null;
    }
    return null;
  }
}
