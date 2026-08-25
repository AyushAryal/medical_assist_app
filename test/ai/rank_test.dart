import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/assist_request.dart';
import 'package:medical_app/ai/intent.dart';
import 'package:medical_app/ai/interpreters/pattern_interpreter.dart';
import 'package:medical_app/ai/preprocess.dart';
import 'package:medical_app/ai/provenance.dart';
import 'package:medical_app/ai/records/rank_parser.dart';

/// Runs a phrase through the pattern interpreter the way the pipeline does,
/// for the projection cases that ride on cohort questions.
Future<AssistIntent?> interpretCohort(String text) {
  final request = AssistRequest(text: text, source: RequestSource.typed);
  return const PatternInterpreter()
      .interpret(request, Preprocessor.run(request, Provenance()));
}

void main() {
  group('the rank parser reads "who stands out"', () {
    test('a superlative that is also the measure', () {
      final spec = RankParser.parse('riskiest patients')!;
      expect(spec.measure.name, 'news2_score');
      expect(spec.descending, isTrue);
      expect(spec.cutoff, isNull);
    });

    test('a qualifier is read as the published screening cut-off', () {
      final spec = RankParser.parse('patients with high bp')!;
      expect(spec.measure.name, 'systolic_bp');
      expect(spec.cutoff, 140);
      expect(spec.descending, isTrue);
      // The word it read and the number it chose both travel with the spec,
      // so the answer can show its reading rather than assert a list.
      expect(spec.qualifier, contains('high'));
    });

    test('"low" cuts at the lower screening bound, worst first', () {
      final spec = RankParser.parse('patients with low sats')!;
      expect(spec.measure.name, 'spo2');
      expect(spec.cutoff, 94);
      expect(spec.descending, isFalse);
    });

    test('a clinical condition word carries measure and direction', () {
      final fever = RankParser.parse('febrile patients')!;
      expect(fever.measure.name, 'temperature_c');
      expect(fever.cutoff, 38);

      final hypoxic = RankParser.parse('hypoxic patients')!;
      expect(hypoxic.measure.name, 'spo2');
      expect(hypoxic.descending, isFalse);
    });

    test('an explicit threshold beats the screening bound', () {
      final spec = RankParser.parse('news2 above 5')!;
      expect(spec.measure.name, 'news2_score');
      expect(spec.cutoff, 5);
      expect(spec.descending, isTrue);

      final low = RankParser.parse('temperature below 36')!;
      expect(low.cutoff, 36);
      expect(low.descending, isFalse);
    });

    test('top N caps the list', () {
      expect(RankParser.parse('top 5 patients by bmi')!.limit, 5);
      expect(RankParser.parse('10 heaviest patients')!.limit, 10);
    });

    test('age superlatives rank the register itself', () {
      final oldest = RankParser.parse('oldest patients')!;
      expect(oldest.table.name, 'patients');
      expect(oldest.measure.name, 'age');
      expect(oldest.descending, isTrue);
      expect(RankParser.parse('youngest patients')!.descending, isFalse);
    });

    // "Highest BMI" with nobody in the sentence is a maximum — the analysis
    // parser's answer — and claiming it here would replace a number with a
    // list nobody asked for.
    test('a bare superlative without a person is declined', () {
      expect(RankParser.parse('highest bmi'), isNull);
      expect(RankParser.parse('lowest heart rate'), isNull);
    });

    // "High" only means something where a published cut-off exists. Guessing
    // a threshold for a field that has none is a diagnosis this app must not
    // invent.
    test('a qualifier with no published cut-off is refused', () {
      expect(RankParser.parse('patients with high age'), isNull);
      expect(RankParser.parse('patients with high height'), isNull);
    });

    test('cohort questions do not leak into rankings', () {
      for (final question in <String>[
        'everyone on warfarin',
        'appointments today',
        'diabetics not seen in 6 months',
        'unsigned notes',
        'average bmi by district',
        'hello',
      ]) {
        expect(RankParser.parse(question), isNull, reason: question);
      }
    });

    test('a period narrows the ranking', () {
      final spec = RankParser.parse(
        'riskiest patients this month',
        asOf: DateTime(2026, 8, 24),
      )!;
      expect(spec.periodFrom, DateTime(2026, 8));
    });
  });

  group('projection reads "and their X" as columns, never filters', () {
    test('a directory request projects contact details', () async {
      final intent = await interpretCohort(
        'patients and their contact numbers',
      ) as QueryIntent;
      expect(intent.projection.map((f) => f.name), <String>['phone']);
      // Columns were asked for, so the table leads.
      expect(intent.preferTable, isTrue);
      // The cohort is unchanged: the whole register, no filter added.
      expect(intent.query.isEmpty, isTrue);
    });

    test('the projection can lead the sentence', () async {
      final intent = await interpretCohort(
        'phone numbers of all patients',
      ) as QueryIntent;
      expect(intent.projection.map((f) => f.name), <String>['phone']);
    });

    test('projection rides on a filtered cohort without changing it', () async {
      final plain =
          await interpretCohort('everyone on warfarin') as QueryIntent;
      final projected = await interpretCohort(
        'everyone on warfarin and their phone numbers',
      ) as QueryIntent;

      expect(projected.query.medication, plain.query.medication);
      expect(projected.projection, isNotEmpty);
    });

    test('several fields, and each resolves or none do', () async {
      final intent = await interpretCohort(
        'patients and their age, phone number and email',
      ) as QueryIntent;
      expect(
        intent.projection.map((f) => f.name),
        containsAll(<String>['age', 'phone', 'email']),
      );

      // "Diabetes" is not a patient attribute, so this is a *filter* and the
      // whole phrase must reach the cohort router untouched.
      final filtered = await interpretCohort('patients with diabetes');
      expect(filtered, isA<QueryIntent>());
      expect((filtered! as QueryIntent).projection, isEmpty);
    });

    test('"as a table" is a rendering preference, not a filter', () async {
      final intent =
          await interpretCohort('appointments today as a table') as QueryIntent;
      expect(intent.preferTable, isTrue);
      expect(intent.query.entity.name, 'appointments');
    });
  });
}
