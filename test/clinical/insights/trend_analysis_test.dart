import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/explanations.dart';
import 'package:medical_app/clinical/insights/trend_analysis.dart';

void main() {
  final base = DateTime(2026, 1, 1);

  List<TrendPoint> series(List<double> values, {int dayStep = 7}) => <TrendPoint>[
        for (var i = 0; i < values.length; i++)
          TrendPoint(at: base.add(Duration(days: i * dayStep)), value: values[i]),
      ];

  TrendResult analyse(
    List<double> values, {
    TrendSensitivity? sensitivity,
    int dayStep = 7,
  }) =>
      TrendAnalysis.analyse(
        label: 'Pulse',
        points: series(values, dayStep: dayStep),
        sensitivity: sensitivity ?? TrendSensitivity.heartRate,
      );

  group('finds what a single reading cannot show', () {
    test('a pulse climbing inside the normal band is still flagged', () {
      // Every one of these is a defensible adult pulse. The direction is the
      // finding, and it is exactly what gets missed in a busy clinic.
      final result = analyse(<double>[70, 82, 95, 106, 118]);

      expect(result.direction, TrendDirection.rising);
      expect(result.concern, TrendConcern.deteriorating);
      expect(result.isNotable, isTrue);
      expect(result.changeOverSpan, greaterThan(30));
    });

    test('falling saturation is the concerning direction for SpO2', () {
      final result = TrendAnalysis.analyse(
        label: 'SpO₂',
        points: series(<double>[99, 97, 95, 93]),
        sensitivity: TrendSensitivity.spo2,
      );

      expect(result.direction, TrendDirection.falling);
      expect(result.concern, TrendConcern.deteriorating);
    });

    test('rising saturation is improvement, not deterioration', () {
      final result = TrendAnalysis.analyse(
        label: 'SpO₂',
        points: series(<double>[90, 93, 96, 99]),
        sensitivity: TrendSensitivity.spo2,
      );

      expect(result.direction, TrendDirection.rising);
      expect(result.concern, TrendConcern.improving);
      expect(result.isNotable, isFalse);
    });

    test('steady weight loss is flagged', () {
      final result = TrendAnalysis.analyse(
        label: 'Weight',
        points: series(<double>[72, 70, 68, 66], dayStep: 30),
        sensitivity: TrendSensitivity.weight,
      );

      expect(result.concern, TrendConcern.deteriorating);
    });
  });

  group('does not manufacture trends', () {
    test('two readings are readings, not a trend', () {
      final result = analyse(<double>[70, 120]);

      expect(result.direction, TrendDirection.tooFewPoints);
      expect(result.concern, TrendConcern.none);
    });

    test('a stable series is steady', () {
      expect(analyse(<double>[72, 74, 71, 73, 72]).direction,
          TrendDirection.steady);
    });

    test('one wild outlier does not create a trend', () {
      // The whole reason for a median-of-slopes fit rather than least squares:
      // a cuff on the wrong arm must not produce a deterioration warning.
      final result = analyse(<double>[72, 74, 190, 71, 73]);

      expect(result.direction, TrendDirection.steady);
      expect(result.isNotable, isFalse);
    });

    test('a scattered series with a slope through it is not a trend', () {
      // Same start and end as the climbing case, but the path is noise. The
      // consistency check is what separates them.
      final result = analyse(<double>[70, 110, 75, 115, 80, 118]);

      expect(result.consistency, lessThan(TrendAnalysis.minimumConsistency));
      expect(result.direction, TrendDirection.steady);
    });

    test('a change too small to matter clinically is steady', () {
      expect(analyse(<double>[72, 74, 76, 78]).direction, TrendDirection.steady);
    });

    test('readings minutes apart do not become a huge daily rate', () {
      // Six observations over half an hour during one visit. Without a floor
      // on the span, dividing by a fraction of a day makes any change enormous.
      final result = analyse(<double>[70, 72, 74, 76, 78, 80], dayStep: 0);

      expect(result.changeOverSpan.abs(), lessThan(20));
      expect(result.direction, TrendDirection.steady);
    });

    test('an empty series is handled', () {
      final result = TrendAnalysis.analyse(
        label: 'Pulse',
        points: const <TrendPoint>[],
        sensitivity: TrendSensitivity.heartRate,
      );
      expect(result.direction, TrendDirection.tooFewPoints);
    });
  });

  test('points out of order are sorted before analysis', () {
    final scrambled = <TrendPoint>[
      TrendPoint(at: base.add(const Duration(days: 14)), value: 118),
      TrendPoint(at: base, value: 70),
      TrendPoint(at: base.add(const Duration(days: 7)), value: 95),
    ];

    final result = TrendAnalysis.analyse(
      label: 'Pulse',
      points: scrambled,
      sensitivity: TrendSensitivity.heartRate,
    );

    expect(result.first, 70);
    expect(result.last, 118);
    expect(result.direction, TrendDirection.rising);
  });

  test('the explanation reports the readings it actually used', () {
    final explanation = TrendAnalysis.explain(
      analyse(<double>[70, 82, 95, 106, 118]),
      'bpm',
    );

    expect(explanation.derivation.first.value, contains('70'));
    expect(explanation.caveat, isNotNull);
    expect(explanation.confidence, ExplainConfidence.heuristic);
  });
}
