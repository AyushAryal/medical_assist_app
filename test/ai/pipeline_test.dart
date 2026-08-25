import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/assist_request.dart';
import 'package:medical_app/ai/intent.dart';
import 'package:medical_app/ai/interpreter.dart';
import 'package:medical_app/ai/interpreters/model_interpreter.dart';
import 'package:medical_app/ai/interpreters/pattern_interpreter.dart';
import 'package:medical_app/ai/preprocess.dart';
import 'package:medical_app/ai/provenance.dart';
import 'package:medical_app/ai/cohort/cohort_query.dart';

AssistRequest ask(String text, {String? actor}) => AssistRequest(
      text: text,
      source: RequestSource.typed,
      actor: actor,
      asOf: DateTime(2026, 8, 24),
    );

void main() {
  group('preprocessing', () {
    test('strips framing so the wrapping does not reach an interpreter', () {
      final wrapped = Preprocessor.run(
        ask('Could you please show me all the patients?'),
        Provenance(),
      );

      // Articles and quantifiers survive on purpose — "no", "all" and "the"
      // can carry meaning, and deciding that is the interpreter's job, not
      // this stage's. What must not survive is the framing.
      for (final framing in <String>['could you', 'please', 'show me', '?']) {
        expect(wrapped.normalised, isNot(contains(framing)), reason: framing);
      }
    });

    test('framing does not change what a request means', () async {
      Future<AssistIntent> interpret(String text) async {
        final request = ask(text);
        final provenance = Provenance();
        return const InterpreterChain(<Interpreter>[PatternInterpreter()])
            .run(request, Preprocessor.run(request, provenance), provenance);
      }

      final plain = await interpret('all patients') as QueryIntent;
      final polite =
          await interpret('Could you please show me all the patients?')
              as QueryIntent;

      expect(polite.query.entity, plain.query.entity);
      expect(polite.query.isEmpty, plain.query.isEmpty);
    });

    test('sets identifiers aside before anything can read them', () {
      // Today every interpreter is coded logic on-device, so this looks like
      // ceremony. It is the opposite: the moment a model is added is the
      // moment it is easiest to forget, and a stage that was always there
      // cannot be forgotten.
      final result = Preprocessor.run(ask('mrn 004512'), Provenance());

      expect(result.redactions, contains('004512'));
      expect(result.normalised, isNot(contains('004512')));
      expect(result.normalised, contains('«id»'));
    });

    test('an identifier can be restored for coded logic that needs it', () {
      final result = Preprocessor.run(ask('mrn 004512'), Provenance());
      expect(Preprocessor.restore(result), contains('004512'));
    });

    test('keeps the original verbatim', () {
      final result = Preprocessor.run(ask('Show me ALL Patients'), Provenance());
      expect(result.original, 'Show me ALL Patients');
    });

    test('records what it did', () {
      final provenance = Provenance();
      Preprocessor.run(ask('please show me all patients'), provenance);

      expect(provenance.steps, hasLength(1));
      expect(provenance.steps.first.stage, 'preprocess');
    });
  });

  group('the interpreter chain', () {
    Future<AssistIntent> run(
      String text, {
      List<Interpreter>? interpreters,
    }) async {
      final request = ask(text);
      final provenance = Provenance();
      final input = Preprocessor.run(request, provenance);
      return InterpreterChain(
        interpreters ?? const <Interpreter>[PatternInterpreter()],
      ).run(request, input, provenance);
    }

    test('pattern matching answers an ordinary question', () async {
      final intent = await run('everyone on warfarin');

      expect(intent, isA<QueryIntent>());
      expect((intent as QueryIntent).query.medication, 'warfarin');
    });

    test('a distribution question becomes a report, not a list', () async {
      // Answering "how is this distributed" with a list is what makes
      // reporting features go unread.
      final intent = await run('visits per week');

      expect(intent, isA<ReportIntent>());
      expect((intent as ReportIntent).kind, ReportKind.activityOverTime);
    });

    test('an MRN survives redaction because coded logic restores it',
        () async {
      final intent = await run('mrn 004512');
      expect((intent as QueryIntent).query.mrn, '004512');
    });

    test('nothing understood yields an intent, not a null', () async {
      // "I did not understand" is a result; it needs provenance too.
      final intent = await run('the and or of');
      expect(intent, isA<UnknownIntent>());
    });

    test('records which interpreter answered, and whether it was a model',
        () async {
      final request = ask('everyone on warfarin');
      final provenance = Provenance();
      final input = Preprocessor.run(request, provenance);
      await const InterpreterChain(<Interpreter>[PatternInterpreter()])
          .run(request, input, provenance);

      final step =
          provenance.steps.firstWhere((s) => s.stage == 'interpret');
      expect(step.summary, contains('pattern matching'));
      expect(step.wasModel, isFalse);
      expect(
        provenance.involvedModel,
        isFalse,
        reason: 'hand-written matching must not be badged as generated',
      );
    });

    test('an unsure interpreter is passed over', () async {
      final intent = await run(
        'everyone on warfarin',
        interpreters: <Interpreter>[
          const _AlwaysUnsure(),
          const PatternInterpreter(),
        ],
      );

      expect(intent, isA<QueryIntent>());
    });

    test('a model interpreter is marked as such in the trail', () async {
      final request = ask('anything');
      final provenance = Provenance();
      final input = Preprocessor.run(request, provenance);

      await const InterpreterChain(<Interpreter>[_FakeModel()])
          .run(request, input, provenance);

      expect(provenance.involvedModel, isTrue);
    });
  });

  group('the post-model gate', () {
    test('rejects a query with no filter at all', () {
      // A query with no filter matches the entire register. Letting one
      // through is what produced "hello → 13 patients".
      expect(
        ModelInterpreter.validate(
          const QueryIntent(
            query: CohortQuery(kind: CohortQueryKind.recall),
            confidence: 0.9,
          ),
        ),
        isFalse,
      );
    });

    test('accepts a query with a real filter', () {
      expect(
        ModelInterpreter.validate(
          const QueryIntent(
            query: CohortQuery(
              kind: CohortQueryKind.recall,
              medication: 'warfarin',
            ),
            confidence: 0.9,
          ),
        ),
        isTrue,
      );
    });

    test('accepts a text-only query, which is a smaller claim', () {
      expect(
        ModelInterpreter.validate(
          const QueryIntent(
            query: CohortQuery(
              kind: CohortQueryKind.recall,
              anyTextOf: <String>['coffee'],
            ),
            confidence: 0.5,
          ),
        ),
        isTrue,
      );
    });

    test('rejects a change with nothing to change or nobody to change it on',
        () {
      expect(
        ModelInterpreter.validate(
          const MutationIntent(
            operation: MutationOperation.update,
            entity: QueryEntity.patients,
            summary: 'change something',
            confidence: 0.9,
          ),
        ),
        isFalse,
      );
    });
  });

  group('provenance', () {
    test('reports the weakest step, not an average', () {
      // An answer is only as trustworthy as its weakest stage, and averaging
      // hides exactly the step worth knowing about.
      final provenance = Provenance()
        ..add('interpret', 'a', confidence: 0.9)
        ..add('execute', 'b', confidence: 0.3);

      expect(provenance.weakestConfidence, 0.3);
    });
  });
}

class _AlwaysUnsure implements Interpreter {
  @override
  bool canRead(AssistRequest request) => request.hasText;

  const _AlwaysUnsure();

  @override
  String get name => 'unsure';

  @override
  String? get modelName => null;

  @override
  Future<AssistIntent?> interpret(AssistRequest r, Preprocessed i) async =>
      const QueryIntent(
        query: CohortQuery(kind: CohortQueryKind.recall, medication: 'wrong'),
        confidence: 0.05,
      );
}

class _FakeModel implements Interpreter {
  @override
  bool canRead(AssistRequest request) => request.hasText;

  const _FakeModel();

  @override
  String get name => 'test model';

  @override
  String? get modelName => 'test-model-v1';

  @override
  Future<AssistIntent?> interpret(AssistRequest r, Preprocessed i) async =>
      const QueryIntent(
        query: CohortQuery(kind: CohortQueryKind.recall, medication: 'aspirin'),
        confidence: 0.8,
      );
}
