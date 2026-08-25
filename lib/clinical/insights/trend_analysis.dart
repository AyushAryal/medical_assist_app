import '../../core/utils/robust_stats.dart';
import 'dart:math' as math;

import '../explanations.dart';

/// One observation in a series.
class TrendPoint {
  const TrendPoint({required this.at, required this.value});

  final DateTime at;
  final double value;
}

/// Which way a series is heading, and whether that is worth saying out loud.
enum TrendDirection { rising, falling, steady, tooFewPoints }

extension TrendDirectionX on TrendDirection {
  String get label => switch (this) {
        TrendDirection.rising => 'rising',
        TrendDirection.falling => 'falling',
        TrendDirection.steady => 'steady',
        TrendDirection.tooFewPoints => 'not enough readings',
      };
}

/// Whether a trend is clinically worth surfacing, and which way is bad.
enum TrendConcern {
  /// Moving the wrong way, consistently, fast enough to matter.
  deteriorating,

  /// Moving, but in the direction treatment intends.
  improving,

  /// Moving, but not in a direction this observation assigns meaning to.
  neutral,

  none,
}

class TrendResult {
  const TrendResult({
    required this.label,
    required this.direction,
    required this.concern,
    required this.slopePerDay,
    required this.changeOverSpan,
    required this.points,
    required this.span,
    required this.first,
    required this.last,
    required this.consistency,
  });

  final String label;
  final TrendDirection direction;
  final TrendConcern concern;

  /// Units per day, from the robust fit.
  final double slopePerDay;

  /// Total modelled change from the first reading to the last.
  final double changeOverSpan;

  final int points;
  final Duration span;
  final double first;
  final double last;

  /// Proportion of consecutive steps that move the same way as the overall
  /// slope, 0–1. A series that climbs, drops and climbs again reaches the same
  /// endpoint as one that climbs steadily, and only the second is a trend.
  final double consistency;

  bool get isNotable => concern == TrendConcern.deteriorating;
}

/// Detects sustained movement in a series of observations.
///
/// This is the one piece of analysis in the app that finds something a reading
/// on its own cannot show. A pulse of 70, then 95, then 118 is three values
/// that may each be inside a reference band, and the patient is nonetheless
/// deteriorating in front of you. Flagging *direction* is what a chart review
/// is for, and it is exactly what gets missed when a clinic is busy.
///
/// Deliberately conservative. A false "deteriorating" costs a clinician a
/// pointless second look, and a handful of those is all it takes for the
/// feature to be ignored — including on the day it is right.
abstract final class TrendAnalysis {
  /// Fewer than this and there is no trend, only readings.
  static const int minimumPoints = 3;

  /// Below this fraction of steps agreeing with the overall direction, the
  /// series is noise with a slope through it.
  ///
  /// Two in three. A simple alternating series — up, down, up, down, up —
  /// reaches exactly 0.6 while being the clearest possible example of
  /// something that is not a trend, so the bar sits above it.
  static const double minimumConsistency = 0.67;

  static TrendResult analyse({
    required String label,
    required List<TrendPoint> points,
    required TrendSensitivity sensitivity,
  }) {
    final sorted = points.toList()..sort((a, b) => a.at.compareTo(b.at));

    if (sorted.length < minimumPoints) {
      return TrendResult(
        label: label,
        direction: TrendDirection.tooFewPoints,
        concern: TrendConcern.none,
        slopePerDay: 0,
        changeOverSpan: 0,
        points: sorted.length,
        span: Duration.zero,
        first: sorted.isEmpty ? 0 : sorted.first.value,
        last: sorted.isEmpty ? 0 : sorted.last.value,
        consistency: 0,
      );
    }

    final span = sorted.last.at.difference(sorted.first.at);
    final spanDays = math.max(span.inMinutes / (60 * 24), _minimumSpanDays);

    final slope = _theilSenSlopePerDay(sorted);
    final change = slope * spanDays;
    final consistency = _consistency(sorted, slope);

    final significant = change.abs() >= sensitivity.minimumChange &&
        consistency >= minimumConsistency;

    final direction = !significant
        ? TrendDirection.steady
        : change > 0
            ? TrendDirection.rising
            : TrendDirection.falling;

    return TrendResult(
      label: label,
      direction: direction,
      concern: switch (direction) {
        TrendDirection.rising => sensitivity.risingIsBad
            ? TrendConcern.deteriorating
            : sensitivity.fallingIsBad
                ? TrendConcern.improving
                : TrendConcern.neutral,
        TrendDirection.falling => sensitivity.fallingIsBad
            ? TrendConcern.deteriorating
            : sensitivity.risingIsBad
                ? TrendConcern.improving
                : TrendConcern.neutral,
        _ => TrendConcern.none,
      },
      slopePerDay: slope,
      changeOverSpan: change,
      points: sorted.length,
      span: span,
      first: sorted.first.value,
      last: sorted.last.value,
      consistency: consistency,
    );
  }

  /// A day, so a burst of observations minutes apart cannot produce an
  /// enormous per-day slope from a small real change.
  static const double _minimumSpanDays = 1.0;

  /// Slope in units per day, robust to a bad reading. See
  /// [RobustStats.theilSenSlope] for why it is not least squares.
  static double _theilSenSlopePerDay(List<TrendPoint> sorted) =>
      RobustStats.theilSenSlope(
        <({double x, double y})>[
          for (final point in sorted)
            (
              x: point.at.millisecondsSinceEpoch / Duration.millisecondsPerDay,
              y: point.value,
            ),
        ],
        // A minute. Two observations that close say nothing about a daily
        // rate, and dividing by that interval invents an enormous slope.
        minimumSpan: 1 / (24 * 60),
      );

  /// How much of the series actually moves the way the fit says it does.
  static double _consistency(List<TrendPoint> sorted, double slope) {
    if (slope == 0 || sorted.length < 2) return 0;
    var agreeing = 0;
    var steps = 0;
    for (var i = 1; i < sorted.length; i++) {
      final delta = sorted[i].value - sorted[i - 1].value;
      if (delta == 0) continue;
      steps++;
      if (delta.sign == slope.sign) agreeing++;
    }
    return steps == 0 ? 0 : agreeing / steps;
  }

  static MetricExplanation explain(TrendResult trend, String unit) {
    final days = trend.span.inDays;
    final spanLabel = days >= 1
        ? '$days day${days == 1 ? '' : 's'}'
        : '${trend.span.inHours} hours';

    return MetricExplanation(
      title: '${trend.label} — ${trend.direction.label}',
      summary: trend.direction == TrendDirection.tooFewPoints
          ? 'At least $minimumPoints readings are needed before direction means '
              'anything.'
          : 'Direction across ${trend.points} readings over $spanLabel. '
              'A value moving steadily matters even when each individual '
              'reading is still inside its reference band.',
      method: <String>[
        'The slope between every possible pair of readings is calculated, and '
            'the middle one of those slopes is taken as the trend.',
        'Taking the middle slope rather than fitting a line means one bad '
            'reading — a cuff on the wrong arm, a temperature after a hot '
            'drink — cannot invent a trend on its own.',
        'The readings are then checked for agreement: '
            '${(trend.consistency * 100).round()}% of the steps move the same '
            'way as the overall slope. Below '
            '${(minimumConsistency * 100).round()}% it is reported as steady, '
            'because scattered readings with a slope through them are not a '
            'trend.',
        'Only a change large enough to be clinically meaningful for this '
            'particular observation is reported.',
      ],
      derivation: <ExplainRow>[
        ExplainRow(
          label: 'First reading',
          value: '${_fmt(trend.first)} $unit',
        ),
        ExplainRow(
          label: 'Latest reading',
          value: '${_fmt(trend.last)} $unit',
        ),
        ExplainRow(
          label: 'Modelled change',
          value: '${trend.changeOverSpan >= 0 ? '+' : '−'}'
              '${_fmt(trend.changeOverSpan.abs())} $unit',
          note: 'over $spanLabel',
        ),
        ExplainRow(
          label: 'Readings agreeing',
          value: '${(trend.consistency * 100).round()}%',
        ),
      ],
      confidence: trend.points < minimumPoints
          ? ExplainConfidence.insufficientData
          : ExplainConfidence.heuristic,
      source: 'Theil–Sen slope estimate — this app',
      caveat: 'This describes the numbers, not the patient. Readings taken in '
          'different circumstances sit on the same line: a course of treatment, '
          'a fever breaking, or observations taken after exertion all produce '
          'a trend that is real in the data and expected in the patient.',
    );
  }

  static String _fmt(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

/// How much movement matters for one particular observation, and which
/// direction is the bad one.
///
/// These thresholds are the whole feature. Set them low and every chart shows
/// a warning; set them high and nothing is ever caught. They are pitched at
/// roughly "a clinician reviewing this chart would comment on it".
class TrendSensitivity {
  const TrendSensitivity({
    required this.minimumChange,
    required this.risingIsBad,
    required this.fallingIsBad,
  });

  /// Smallest total change, in the observation's own units, worth reporting.
  final double minimumChange;
  final bool risingIsBad;
  final bool fallingIsBad;

  /// A sustained climb in systolic pressure. A fall matters too, but a falling
  /// pressure is usually either treatment working or an acute event that the
  /// early warning score has already caught.
  static const TrendSensitivity systolic = TrendSensitivity(
    minimumChange: 15,
    risingIsBad: true,
    fallingIsBad: false,
  );

  /// A climbing resting pulse across visits is one of the earliest signs of
  /// something developing.
  static const TrendSensitivity heartRate = TrendSensitivity(
    minimumChange: 15,
    risingIsBad: true,
    fallingIsBad: false,
  );

  static const TrendSensitivity respiratoryRate = TrendSensitivity(
    minimumChange: 5,
    risingIsBad: true,
    fallingIsBad: false,
  );

  /// Falling saturation is the concerning direction, and the band that matters
  /// is narrow — a drop of 4 points is a lot.
  static const TrendSensitivity spo2 = TrendSensitivity(
    minimumChange: 4,
    risingIsBad: false,
    fallingIsBad: true,
  );

  /// Unintended weight loss is a red flag across almost all of medicine.
  /// Weight gain matters too but far more slowly, so only loss is flagged.
  static const TrendSensitivity weight = TrendSensitivity(
    minimumChange: 4,
    risingIsBad: false,
    fallingIsBad: true,
  );

  static const TrendSensitivity temperature = TrendSensitivity(
    minimumChange: 1.0,
    risingIsBad: true,
    fallingIsBad: false,
  );

  static const TrendSensitivity glucose = TrendSensitivity(
    minimumChange: 3.0,
    risingIsBad: true,
    fallingIsBad: true,
  );
}
