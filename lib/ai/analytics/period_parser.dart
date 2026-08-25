/// Reads "this month", "last year", "in the last 6 weeks" off a question.
///
/// Its own file because two grammars need it — the analysis parser and the
/// ranking parser — and a period is exactly the kind of phrase that must mean
/// the same thing everywhere. Two copies of "last month" is how a chart and
/// the ranked list beside it come to disagree about when the month started.
abstract final class PeriodParser {
  static ({DateTime? from, DateTime? to, String rest}) take(
    String text,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);

    ({DateTime? from, DateTime? to, String rest}) hit(
      String phrase,
      DateTime? from,
      DateTime? to,
    ) =>
        (from: from, to: to, rest: _squash(text.replaceFirst(phrase, ' ')));

    final relative = RegExp(
      r'\b(?:in the )?(?:last|past|previous)\s+(\d+)\s+'
      r'(day|week|month|year)s?\b',
    ).firstMatch(text);
    if (relative != null) {
      final count = int.parse(relative.group(1)!);
      final from = switch (relative.group(2)!) {
        'day' => today.subtract(Duration(days: count)),
        'week' => today.subtract(Duration(days: 7 * count)),
        'month' => DateTime(now.year, now.month - count, now.day),
        _ => DateTime(now.year - count, now.month, now.day),
      };
      return (
        from: from,
        to: null,
        rest: _squash(text.replaceRange(relative.start, relative.end, ' ')),
      );
    }

    if (text.contains('this month')) {
      return hit('this month', DateTime(now.year, now.month), null);
    }
    if (text.contains('last month')) {
      return hit(
        'last month',
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month),
      );
    }
    if (text.contains('this year')) {
      return hit('this year', DateTime(now.year), null);
    }
    if (text.contains('last year')) {
      return hit('last year', DateTime(now.year - 1), DateTime(now.year));
    }
    if (text.contains('this week')) {
      return hit(
        'this week',
        today.subtract(Duration(days: today.weekday - 1)),
        null,
      );
    }
    return (from: null, to: null, rest: text);
  }

  /// Collapses the hole left by a removed phrase. Deliberately *not* the
  /// callers' full tidying — each grammar strips its own filler after this.
  static String _squash(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
