import 'intent.dart';

/// One exchange: what was asked, what it was understood as, what came back.
class AssistTurn {
  const AssistTurn({
    required this.question,
    required this.intent,
    required this.headline,
  });

  final String question;
  final AssistIntent intent;

  /// The answer's one-line reading, kept so a transcript can be rebuilt on
  /// any surface without re-running the queries behind it.
  final String headline;
}

/// The conversation, held by the pipeline and shared by every surface.
///
/// This is what makes the assistant a dialogue instead of a search box that
/// forgets. The bubble, the Ask page, and any future surface all read and
/// write the same thread, so "patients on warfarin" asked in the bubble and
/// "only the women" typed on the full page are one conversation — expanding
/// the bubble hands over the *state*, not just the last string.
///
/// It lives inside the pipeline, which is torn down on lock like everything
/// else that has touched patient data. A conversation about a register is
/// PHI; it does not outlive the unlock that produced it.
class AssistThread {
  AssistThread();

  /// Enough for "of those" to always have a referent, small enough that the
  /// summary stays a sentence. Older turns fall off the front.
  static const int _capacity = 12;

  final List<AssistTurn> _turns = <AssistTurn>[];

  List<AssistTurn> get turns => List.unmodifiable(_turns);

  bool get isEmpty => _turns.isEmpty;

  /// The intent a fragment refines: the most recent one that actually did
  /// something. Clarifications and misfires are skipped — "only the women"
  /// after a question the app did not understand refers to the last real
  /// answer, not to the failure.
  AssistIntent? get standingIntent {
    for (final turn in _turns.reversed) {
      if (turn.intent is! UnknownIntent) return turn.intent;
    }
    return null;
  }

  String? get lastQuestion => _turns.isEmpty ? null : _turns.last.question;

  /// What the conversation is currently about, as one line.
  ///
  /// Deterministic — built from the standing intent's own description, the
  /// same words already shown as filters — so the summary can never claim
  /// something the filters do not. Shown as the context strip above the
  /// composer, because a conversation the user cannot see the state of is a
  /// conversation they cannot correct.
  String? get summary {
    final standing = standingIntent;
    if (standing == null) return null;
    final parts = standing.describe();
    final line = parts.take(3).join(' · ');
    return line.isEmpty ? null : line;
  }

  /// Distinct earlier questions, latest first — the recap, and the tappable
  /// way back to any of them.
  List<String> get askedSoFar {
    final seen = <String>{};
    final out = <String>[];
    for (final turn in _turns.reversed) {
      if (turn.intent is UnknownIntent) continue;
      if (seen.add(turn.question)) out.add(turn.question);
    }
    return out;
  }

  void remember(AssistTurn turn) {
    _turns.add(turn);
    if (_turns.length > _capacity) _turns.removeAt(0);
  }

  void clear() => _turns.clear();
}
