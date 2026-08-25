/// A structured account of where a displayed number came from.
///
/// Every derived value in this app — an early warning score, a reference-range
/// flag, a "needs attention" row, a no-show risk — is the output of a rule that
/// the clinician did not write and cannot see. That is a trust problem, and it
/// is the reason clinicians abandon decision support: a number with no visible
/// derivation is either believed uncritically or ignored entirely, and both are
/// worse than showing the working.
///
/// So the rule in this codebase is: **anything computed carries an
/// explanation**. Not a tooltip restating the label, but the actual method, the
/// actual inputs for *this* patient, and the source it comes from.
///
/// Pure Dart, no Flutter imports — the text and the derivation are unit-tested
/// alongside the calculators that produce them.
library;

/// One line of the working: an input, its value, and what it contributed.
class ExplainRow {
  const ExplainRow({
    required this.label,
    required this.value,
    this.contribution,
    this.note,
  });

  /// What was measured — `Respiratory rate`, `Prior no-shows`.
  final String label;

  /// The value used, already formatted for display with its unit.
  final String value;

  /// What that input added to the result, when the result is a sum. Null for
  /// explanations that are not additive.
  final String? contribution;

  /// Why this input scored what it did — the band it fell in, typically.
  final String? note;
}

/// How much confidence the reader should place in the number.
enum ExplainConfidence {
  /// A fixed formula on values that were actually measured. Reproducible.
  measured,

  /// A published, validated instrument applied within its stated scope.
  validated,

  /// A heuristic this app defines. Useful for ordering a list; not evidence.
  heuristic,

  /// Not enough data to be meaningful yet — shown so the reader knows why the
  /// figure looks flat or absent.
  insufficientData,
}

extension ExplainConfidenceX on ExplainConfidence {
  String get label => switch (this) {
        ExplainConfidence.measured => 'Calculated',
        ExplainConfidence.validated => 'Validated score',
        ExplainConfidence.heuristic => 'Estimate',
        ExplainConfidence.insufficientData => 'Not enough data',
      };

  /// One line on how much weight the figure can carry. Deliberately blunt
  /// about the heuristics: an estimate this app invented must never be
  /// mistaken for a validated instrument.
  String get meaning => switch (this) {
        ExplainConfidence.measured =>
          'A fixed formula applied to values that were measured and recorded. '
              'Given the same inputs it always returns the same result.',
        ExplainConfidence.validated =>
          'A published clinical instrument, applied only within the scope its '
              'authors validated it for. Decision support, never a diagnosis.',
        ExplainConfidence.heuristic =>
          'A rule of thumb defined by this app to help order a list. It is not '
              'a validated clinical instrument and carries no evidence base — '
              'treat it as a prompt to look, nothing more.',
        ExplainConfidence.insufficientData =>
          'There is not yet enough recorded history for this figure to mean '
              'anything. It will become useful as more is recorded.',
      };
}

/// Everything needed to answer "where did this number come from?".
class MetricExplanation {
  const MetricExplanation({
    required this.title,
    required this.summary,
    this.method = const <String>[],
    this.derivation = const <ExplainRow>[],
    this.confidence = ExplainConfidence.measured,
    this.total,
    this.source,
    this.caveat,
  });

  /// The name of the thing being explained, matching the label on screen.
  final String title;

  /// One sentence: what this number actually means. Not what it is called.
  final String summary;

  /// The method, in order. Each entry is one step a reader could reproduce
  /// with a calculator.
  final List<String> method;

  /// The inputs that produced the value currently on screen. Empty for a
  /// generic explanation of a metric with no single instance behind it.
  final List<ExplainRow> derivation;

  final ExplainConfidence confidence;

  /// The result, restated with its units, when [derivation] sums to it.
  final String? total;

  /// Where the rule comes from — a published standard, or this app.
  final String? source;

  /// The thing a reader would get wrong if it were not said out loud.
  final String? caveat;

  bool get hasDerivation => derivation.isNotEmpty;
}
