import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/analytics/analysis.dart';
import 'package:medical_app/ai/analytics/analysis_engine.dart';
import 'package:medical_app/ai/analytics/analysis_examples.dart';
import 'package:medical_app/ai/analytics/analysis_parser.dart';
import 'package:medical_app/ai/analytics/statistics.dart';
import 'package:medical_app/ai/schema/field_registry.dart';

/// Builds the row shape the DAO returns, so the engine can be tested without a
/// database — which is the point of the split.
Map<String, Object?> row(Map<String, Object?> subject,
        [Map<String, Object?> patient = const <String, Object?>{}]) =>
    <String, Object?>{
      for (final entry in subject.entries) 's_${entry.key}': entry.value,
      for (final entry in patient.entries) 'p_${entry.key}': entry.value,
    };

({List<Map<String, Object?>> rows, bool truncated}) data(
  List<Map<String, Object?>> rows,
) =>
    (rows: rows, truncated: false);

void main() {
  group('the registry finds fields by the words people use', () {
    test('a synonym beats the column name', () {
      final match = FieldRegistry.resolveField('blood pressure');
      expect(match, isNotNull);
      expect(match!.field.name, 'systolic_bp');
      expect(match.table.name, 'vitals');
    });

    test('near-misses and abbreviations land', () {
      for (final probe in <({String said, String field})>[
        (said: 'sats', field: 'spo2'),
        (said: 'pulse', field: 'heart_rate'),
        (said: 'temp', field: 'temperature_c'),
        (said: 'blood sugar', field: 'blood_glucose_mmol'),
        (said: 'early warning score', field: 'news2_score'),
        (said: 'waiting time', field: 'wait_minutes'),
        (said: 'doctor', field: 'provider_name'),
      ]) {
        final match = FieldRegistry.resolveField(probe.said);
        expect(match?.field.name, probe.field,
            reason: '"${probe.said}" should reach ${probe.field}');
      }
    });

    // The alternative — matching whatever scores highest — charts a
    // neighbouring column with total confidence and nothing on screen
    // contradicts it. Declining is the safe failure.
    test('a word that is nothing like a field is refused', () {
      expect(FieldRegistry.resolveField('quantum flux'), isNull);
      expect(FieldRegistry.resolveField('xyzzy'), isNull);
    });

    test('tables answer to their clinical names', () {
      expect(FieldRegistry.resolveTable('observations')?.table.name, 'vitals');
      expect(FieldRegistry.resolveTable('consultation')?.table.name,
          'encounters');
      expect(FieldRegistry.resolveTable('diagnoses')?.table.name, 'problems');
    });
  });

  group('the parser reads analytical questions', () {
    test('aggregate, measure and dimension across two tables', () {
      final spec = AnalysisParser.parse('average blood pressure by district');
      expect(spec, isNotNull);
      expect(spec!.aggregate, Aggregate.average);
      expect(spec.measure?.name, 'systolic_bp');
      // The measure decides the table; the patient attribute joins onto it.
      expect(spec.table.name, 'vitals');
      expect(spec.dimension?.name, 'district');
      expect(spec.dimensionTable?.name, 'patients');
    });

    test('an explicitly named table wins over the dimension it is cut by', () {
      final spec = AnalysisParser.parse('visits by city');
      expect(spec!.table.name, 'encounters');
      expect(spec.dimension?.name, 'city');
      expect(spec.dimensionTable?.name, 'patients');
    });

    test('a named chart overrides the automatic choice', () {
      expect(
        AnalysisParser.parse('appointments by status as a pie chart')?.style,
        ChartStyle.pie,
      );
      expect(
        AnalysisParser.parse('visits per month as a line chart')?.style,
        ChartStyle.line,
      );
    });

    test('two numeric fields become a scatter', () {
      final spec = AnalysisParser.parse('weight against height');
      expect(spec!.isScatter, isTrue);
      expect(spec.measure?.name, 'weight_kg');
      expect(spec.against?.name, 'height_cm');
      expect(spec.styleFor(0), ChartStyle.scatter);
    });

    test('a grain word makes a timeline of the table it belongs to', () {
      final spec = AnalysisParser.parse('appointments per month');
      expect(spec!.bucket, TimeBucket.month);
      expect(spec.dimension?.name, 'scheduled_at');
      expect(spec.isTimeline, isTrue);
    });

    test('a period is a filter, not a grain', () {
      final asOf = DateTime(2026, 6, 15);
      final spec = AnalysisParser.parse(
        'average waiting time in the last 3 months by clinician',
        asOf: asOf,
      );
      expect(spec!.measure?.name, 'wait_minutes');
      expect(spec.dimension?.name, 'provider_name');
      expect(spec.periodFrom, DateTime(2026, 3, 15));
      // Not read as "per month".
      expect(spec.isTimeline, isFalse);
    });

    test('distribution asks for a histogram of one field', () {
      final spec = AnalysisParser.parse('spread of systolic bp');
      expect(spec!.style, ChartStyle.histogram);
      expect(spec.measure?.name, 'systolic_bp');
      expect(spec.dimension, isNull);
    });

    // Everything below belongs to the cohort matcher, which answers with the
    // records behind the number. Parsing them here would replace an openable
    // list with a single bar.
    test('cohort questions are handed back', () {
      for (final question in <String>[
        'appointments today',
        'patients',
        'everyone on warfarin',
        'unsigned notes',
        'diabetics not seen in 6 months',
        'how many visits last month',
        'hello',
        '',
      ]) {
        expect(AnalysisParser.parse(question), isNull,
            reason: '"$question" is not an analysis');
      }
    });

    test('prose cannot be a dimension', () {
      // One bar per record is a table drawn badly.
      expect(AnalysisParser.parse('visits by presenting complaint'), isNull);
    });
  });

  // The loop that keeps the suggestion list honest. Every question the app
  // offers is generated from the registry and walked back through the parser,
  // so a renamed field or a changed synonym fails the build rather than
  // shipping a button that comes back empty.
  test('every suggested chart question parses into the chart it promises', () {
    for (final example in AnalysisExamples.all) {
      final spec = AnalysisParser.parse(example.question);
      expect(spec, isNotNull,
          reason: '"${example.question}" is offered but does not parse');
      expect(
        spec!.styleFor(4),
        example.style,
        reason: '"${example.question}" promises ${example.style} but would '
            'draw ${spec.styleFor(4)}',
      );
    }
  });

  group('the engine only draws what the data supports', () {
    test('categories are ordered by size and carry their row counts', () {
      final spec = AnalysisSpec(
        table: FieldRegistry.encounters,
        aggregate: Aggregate.count,
        dimension: FieldRegistry.encounters.field('type'),
        dimensionTable: FieldRegistry.encounters,
      );
      final result = AnalysisEngine.run(
        spec,
        data(<Map<String, Object?>>[
          row(<String, Object?>{'type': 'followUp'}),
          row(<String, Object?>{'type': 'followUp'}),
          row(<String, Object?>{'type': 'followUp'}),
          row(<String, Object?>{'type': 'emergency'}),
        ]),
      );

      expect(result.points.first.label, 'Follow-up');
      expect(result.points.first.value, 3);
      expect(result.points.first.n, 3);
      expect(result.points.last.label, 'Emergency');
      // Two categories that sum to the whole: a share reads better than bars.
      expect(result.style, ChartStyle.donut);
    });

    test('a long tail is folded, so the parts still sum to the total', () {
      final spec = AnalysisSpec(
        table: FieldRegistry.medications,
        aggregate: Aggregate.count,
        dimension: FieldRegistry.medications.field('name'),
        dimensionTable: FieldRegistry.medications,
        maxGroups: 4,
      );
      final result = AnalysisEngine.run(
        spec,
        data(<Map<String, Object?>>[
          for (var i = 0; i < 20; i++) row(<String, Object?>{'name': 'drug$i'}),
        ]),
      );

      expect(result.points.length, 4);
      expect(result.points.last.label, startsWith('Other'));
      expect(result.total, 20, reason: 'folding must preserve the total');
      expect(result.caveats.any((c) => c.contains('Other')), isTrue);
    });

    test('an average of averages is never folded into "Other"', () {
      final spec = AnalysisSpec(
        table: FieldRegistry.vitals,
        aggregate: Aggregate.average,
        measure: FieldRegistry.vitals.field('systolic_bp'),
        dimension: FieldRegistry.vitals.field('recorded_by'),
        dimensionTable: FieldRegistry.vitals,
        maxGroups: 2,
      );
      final result = AnalysisEngine.run(
        spec,
        data(<Map<String, Object?>>[
          row(<String, Object?>{'recorded_by': 'a', 'systolic_bp': 200}),
          row(<String, Object?>{'recorded_by': 'b', 'systolic_bp': 100}),
          row(<String, Object?>{'recorded_by': 'c', 'systolic_bp': 100}),
        ]),
      );
      // The tail becomes a row count, never a mean of means.
      expect(result.points.last.label, startsWith('Other'));
      expect(result.points.last.value, lessThanOrEqualTo(2));
    });

    test('a missing reading is not a reading of zero', () {
      final spec = AnalysisSpec(
        table: FieldRegistry.vitals,
        aggregate: Aggregate.average,
        measure: FieldRegistry.vitals.field('bmi'),
      );
      final result = AnalysisEngine.run(
        spec,
        data(<Map<String, Object?>>[
          row(<String, Object?>{'bmi': 20.0}),
          row(<String, Object?>{'bmi': 30.0}),
          row(<String, Object?>{'bmi': null}),
          row(<String, Object?>{'bmi': null}),
        ]),
      );

      expect(result.points.first.value, 25);
      expect(result.missing, 2);
      expect(result.stats!.completeness, 0.5);
    });

    test('a quiet week stays quiet, and an unknown average stays unknown', () {
      final week = const Duration(days: 7);
      final start = DateTime(2026, 3, 2);
      final spec = AnalysisSpec(
        table: FieldRegistry.encounters,
        aggregate: Aggregate.count,
        dimension: FieldRegistry.encounters.field('started_at'),
        dimensionTable: FieldRegistry.encounters,
        bucket: TimeBucket.week,
      );
      final result = AnalysisEngine.run(
        spec,
        data(<Map<String, Object?>>[
          row(<String, Object?>{
            'started_at': start.millisecondsSinceEpoch,
          }),
          // Nothing in the middle week.
          row(<String, Object?>{
            'started_at':
                start.add(week * 2).millisecondsSinceEpoch,
          }),
        ]),
      );

      expect(result.points.length, 3, reason: 'the empty week is drawn');
      expect(result.points[1].value, 0);

      // The same gap under an average is unknown rather than zero: drawing it
      // as zero invents a crash that never happened.
      final averaged = AnalysisEngine.run(
        spec.copyWith(aggregate: Aggregate.average),
        data(<Map<String, Object?>>[
          row(<String, Object?>{
            'started_at': start.millisecondsSinceEpoch,
          }),
          row(<String, Object?>{
            'started_at': start.add(week * 2).millisecondsSinceEpoch,
          }),
        ]),
      );
      expect(averaged.points[1].value.isNaN, isTrue);
    });

    test('a scatter reports how closely two fields move together', () {
      final spec = AnalysisSpec(
        table: FieldRegistry.vitals,
        aggregate: Aggregate.average,
        measure: FieldRegistry.vitals.field('weight_kg'),
        against: FieldRegistry.vitals.field('height_cm'),
        againstTable: FieldRegistry.vitals,
        style: ChartStyle.scatter,
      );
      final result = AnalysisEngine.run(
        spec,
        data(<Map<String, Object?>>[
          for (var i = 0; i < 12; i++)
            row(<String, Object?>{
              'height_cm': 150.0 + i * 2,
              'weight_kg': 50.0 + i * 2,
            }),
        ]),
      );

      expect(result.style, ChartStyle.scatter);
      expect(result.correlation!.r, closeTo(1, 0.001));
      // Co-movement is not causation, and the caveat travels with the number.
      expect(
        result.caveats.any((c) => c.contains('not one causing the other')),
        isTrue,
      );
    });
  });

  group('statistics', () {
    test('quartiles match the spreadsheet definition', () {
      final stats = Stats.of(<double>[1, 2, 3, 4, 5])!;
      expect(stats.median, 3);
      expect(stats.q1, 2);
      expect(stats.q3, 4);
      expect(stats.mean, 3);
    });

    test('a transcription slip shows up as an outlier, not in the mean', () {
      // 1800 for 180. Tukey's fences catch it; a standard-deviation rule does
      // not, because the slip inflates the deviation that would have caught it.
      final values = <double>[118, 122, 130, 126, 119, 124, 1800];
      expect(Stats.outliers(values), contains(1800));
    });

    test('one bad week does not invert a trend', () {
      // Rising, with a closed clinic in the middle.
      final trend = Trend.of(<double>[10, 12, 0, 16, 18, 20])!;
      expect(trend.direction, 'rising');
    });

    // "Rising" is a fact; "worse" is the thing a reader is working out, and
    // for a waiting time the two are the same news while for oxygen
    // saturation they are opposite.
    test('a direction is read as good or bad news where the field has one', () {
      final rising = Trend.of(<double>[10, 14, 18, 22])!;
      expect(rising.readingFor(higherIsBetter: false), 'getting worse');
      expect(rising.readingFor(higherIsBetter: true), 'improving');
      // A count of visits going up is neither.
      expect(rising.readingFor(higherIsBetter: null), isNull);
      // And a flat line is not news in either direction.
      expect(
        Trend.of(<double>[10, 10, 10])!.readingFor(higherIsBetter: false),
        isNull,
      );
    });

    test('a flat series is called steady rather than given a direction', () {
      expect(Trend.of(<double>[20, 20, 20, 20])!.direction, 'steady');
    });

    test('correlation is refused where there is nothing to correlate', () {
      expect(Correlation.of(<({double x, double y})>[]), isNull);
      expect(
        Correlation.of(<({double x, double y})>[
          (x: 1, y: 5),
          (x: 1, y: 6),
          (x: 1, y: 7),
        ]),
        isNull,
        reason: 'a constant x has no relationship to describe',
      );
    });
  });
}
