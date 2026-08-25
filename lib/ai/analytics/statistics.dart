import 'dart:math' as math;

import '../../core/utils/robust_stats.dart';

/// Descriptive statistics for one numeric series.
///
/// Computed in Dart rather than in SQL, and that is a decision rather than a
/// shortcut. A median, a quartile and a standard deviation each want a
/// different SQL dialect trick or a window function, whereas the register on
/// one device is small enough to read a column into memory — so one query
/// returns the values and everything below is arithmetic that can be unit
/// tested without a database.
class Stats {
  const Stats({
    required this.count,
    required this.missing,
    required this.mean,
    required this.median,
    required this.min,
    required this.max,
    required this.sd,
    required this.q1,
    required this.q3,
    required this.sum,
  });

  final int count;

  /// Rows that had no value. Reported rather than silently dropped: "average
  /// BMI 24.1" over six of two hundred patients is a different claim from the
  /// same number over all of them.
  final int missing;

  final double mean;
  final double median;
  final double min;
  final double max;

  /// Population standard deviation, or 0 for a single value.
  final double sd;

  final double q1;
  final double q3;
  final double sum;

  double get iqr => q3 - q1;

  /// How much of the data was usable, 0–1.
  double get completeness =>
      count + missing == 0 ? 0 : count / (count + missing);

  static Stats? of(List<double> values, {int missing = 0}) {
    if (values.isEmpty) return null;
    final sorted = List<double>.of(values)..sort();
    final n = sorted.length;
    final sum = sorted.fold<double>(0, (a, b) => a + b);
    final mean = sum / n;
    final variance =
        sorted.fold<double>(0, (a, b) => a + math.pow(b - mean, 2)) / n;

    return Stats(
      count: n,
      missing: missing,
      mean: mean,
      median: _quantile(sorted, 0.5),
      min: sorted.first,
      max: sorted.last,
      sd: math.sqrt(variance),
      q1: _quantile(sorted, 0.25),
      q3: _quantile(sorted, 0.75),
      sum: sum,
    );
  }

  /// Linear interpolation between order statistics — the same definition
  /// spreadsheets use, so a number here matches one someone checks by hand.
  static double _quantile(List<double> sorted, double p) {
    if (sorted.length == 1) return sorted.first;
    final position = (sorted.length - 1) * p;
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  }

  /// Values far enough out to be worth a second look.
  ///
  /// Tukey's fences rather than a standard-deviation rule, because clinical
  /// measurements are skewed and a transcription slip — 1800 mmHg for 180 —
  /// drags a mean and its SD far enough to hide itself.
  static List<double> outliers(List<double> values) {
    final stats = of(values);
    if (stats == null || values.length < 5) return const <double>[];
    final low = stats.q1 - 1.5 * stats.iqr;
    final high = stats.q3 + 1.5 * stats.iqr;
    return values.where((v) => v < low || v > high).toList();
  }
}

/// The relationship between two numeric series.
class Correlation {
  const Correlation({required this.r, required this.n});

  /// Pearson's r, −1 to 1.
  final double r;
  final int n;

  /// Deliberately hedged wording.
  ///
  /// A coefficient invites a causal reading — "waiting time drives
  /// satisfaction" — from what is only co-movement in a register that was not
  /// designed as an experiment. The strength is stated; the direction of cause
  /// is not, and the caveat travels with the number in the explanation.
  String get strength => switch (r.abs()) {
        < 0.1 => 'no real relationship',
        < 0.3 => 'a weak relationship',
        < 0.5 => 'a moderate relationship',
        < 0.7 => 'a fairly strong relationship',
        _ => 'a strong relationship',
      };

  String get direction => r >= 0 ? 'rises with' : 'falls as';

  /// Below this, the coefficient is describing noise.
  bool get isMeaningful => n >= 8 && r.abs() >= 0.1;

  static Correlation? of(List<({double x, double y})> points) {
    if (points.length < 3) return null;
    final n = points.length;
    final meanX = points.fold<double>(0, (a, p) => a + p.x) / n;
    final meanY = points.fold<double>(0, (a, p) => a + p.y) / n;

    var covariance = 0.0;
    var varianceX = 0.0;
    var varianceY = 0.0;
    for (final point in points) {
      final dx = point.x - meanX;
      final dy = point.y - meanY;
      covariance += dx * dy;
      varianceX += dx * dx;
      varianceY += dy * dy;
    }
    if (varianceX == 0 || varianceY == 0) return null;

    return Correlation(
      r: covariance / math.sqrt(varianceX * varianceY),
      n: n,
    );
  }
}

/// The direction a series is moving in.
class Trend {
  const Trend({required this.slopePerStep, required this.first, required this.last});

  /// Change per bucket — per week if the buckets are weeks.
  final double slopePerStep;
  final double first;
  final double last;

  bool get isFlat => slopePerStep.abs() < 0.005 * math.max(1, first.abs());

  String get direction => isFlat
      ? 'steady'
      : slopePerStep > 0
          ? 'rising'
          : 'falling';

  /// The direction in terms of whether it is good news.
  ///
  /// "Rising" is a fact; "getting worse" is what the reader is actually trying
  /// to work out, and for a waiting time or an early-warning score the two are
  /// opposite. Null where the field has no better direction — a count of
  /// visits going up is neither.
  String? readingFor({required bool? higherIsBetter}) {
    if (higherIsBetter == null || isFlat) return null;
    final rising = slopePerStep > 0;
    return rising == higherIsBetter ? 'improving' : 'getting worse';
  }

  /// Median of pairwise slopes, not least squares.
  ///
  /// One catastrophic bucket — a clinic closed, a device broken — swings a
  /// least-squares line hard enough to invert the reported direction. The
  /// median slope ignores it, which is the honest answer about the underlying
  /// direction. Shared with the vitals deterioration check, which needs the
  /// same property for the same reason.
  static Trend? of(List<double> series) {
    if (series.length < 3) return null;
    return Trend(
      slopePerStep: RobustStats.theilSenSlope(<({double x, double y})>[
        for (var i = 0; i < series.length; i++) (x: i.toDouble(), y: series[i]),
      ]),
      first: series.first,
      last: series.last,
    );
  }
}
