import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/assist_request.dart';
import 'package:medical_app/ai/follow_ups.dart';
import 'package:medical_app/ai/intent.dart';
import 'package:medical_app/ai/interpreter.dart';
import 'package:medical_app/ai/interpreters/analysis_interpreter.dart';
import 'package:medical_app/ai/interpreters/overview_interpreter.dart';
import 'package:medical_app/ai/interpreters/pattern_interpreter.dart';
import 'package:medical_app/ai/interpreters/rank_interpreter.dart';
import 'package:medical_app/ai/preprocess.dart';
import 'package:medical_app/ai/provenance.dart';
import 'package:medical_app/ai/cohort/query_vocabulary.dart';

/// Runs a phrase through the interpreters the way the pipeline does — the
/// full chain in pipeline order, because the starters advertise the whole
/// assistant, not one matcher.
Future<AssistIntent?> interpret(String text) async {
  final request = AssistRequest(text: text, source: RequestSource.typed);
  final input = Preprocessor.run(request, Provenance());
  const chain = <Interpreter>[
    OverviewInterpreter(),
    RankInterpreter(),
    AnalysisInterpreter(),
    PatternInterpreter(),
  ];
  for (final interpreter in chain) {
    final intent = await interpreter.interpret(request, input);
    if (intent != null) return intent;
  }
  return null;
}

void main() {
  group('follow-up buttons are questions the app can answer', () {
    // The contract that makes a button honest: appended to a *filtered*
    // cohort, each re-cut phrase must reach the report path with the filter
    // intact. (Unfiltered "visits per week" legitimately goes to the richer
    // analysis engine instead — the danger these guard is a chip that drops
    // the warfarin filter on its way to a chart.)
    for (final kind in ReportKind.values) {
      test('"${kind.phrase}" re-cuts a filtered cohort as ${kind.name}',
          () async {
        final intent = await interpret('diabetics ${kind.phrase}');
        expect(intent, isA<ReportIntent>());
        final report = intent! as ReportIntent;
        expect(report.kind, kind);
        expect(report.query.problem, isNotNull,
            reason: 'the diabetes filter must survive the re-cut');
      });
    }

    test('a cut replaces the previous one rather than stacking', () async {
      var text = 'diabetics this month';
      for (final kind in <ReportKind>[
        ReportKind.bySex,
        ReportKind.activityOverTime,
        ReportKind.byAgeBand,
      ]) {
        final follow = FollowUps.after(
          text: text,
          intent: (await interpret(text))!,
        ).firstWhere((f) => f.label == kind.shortLabel);
        text = follow.text;
      }

      // Not "diabetics this month by sex per week by age band".
      expect(text, 'diabetics this month by age band');
      final last = (await interpret(text))! as ReportIntent;
      expect(last.kind, ReportKind.byAgeBand);
    });

    test('stripping a cut leaves no stray words behind', () {
      expect(
        PatternInterpreter.withoutReportPhrase(
          'visits broken down by age band',
        ),
        'visits',
      );
      expect(
        PatternInterpreter.withoutReportPhrase('appointments by status'),
        'appointments',
      );
    });

    test('a chart offers the way back to the records', () async {
      final intent = await interpret('diabetics per week');
      final follows =
          FollowUps.after(text: 'diabetics per week', intent: intent!);
      expect(follows.first.label, 'Show the list');
      expect(await interpret(follows.first.text), isA<QueryIntent>());
    });

    // Rankings offer their own next moves, and each must route: the spread
    // behind the extremes, the trend of the average, and a longer list.
    test('every ranking follow-up routes', () async {
      final intent = (await interpret('riskiest patients'))!;
      final follows = FollowUps.after(text: 'riskiest patients', intent: intent);
      expect(follows, isNotEmpty);
      for (final follow in follows) {
        expect(
          await interpret(follow.text),
          isNot(isA<UnknownIntent>()),
          reason: '"${follow.text}" is offered after a ranking but fails',
        );
        expect(await interpret(follow.text), isNotNull,
            reason: '"${follow.text}" routed to nothing');
      }
    });

    test('only cuts that mean something for the entity are offered', () async {
      final patients = FollowUps.after(
        text: 'patients on warfarin',
        intent: (await interpret('patients on warfarin'))!,
      ).map((f) => f.label);
      // Visit type is a property of a visit; a patient does not have one.
      expect(patients, isNot(contains('By visit type')));
      expect(patients, contains('By age'));
    });

    test('a question that was not understood is not given re-cuts', () {
      expect(
        FollowUps.after(
          text: 'hello',
          intent: const UnknownIntent(reason: 'No.'),
        ),
        isEmpty,
      );
    });

    // The list on the empty state is a promise. Anything offered there has to
    // route, or the first thing someone does with this feature is watch a
    // button the app itself suggested come back with "I did not understand".
    test('every starter offered on the Ask page actually answers', () async {
      for (final group in QueryVocabulary.starters) {
        for (final starter in group.starters) {
          expect(
            await interpret(starter),
            isA<AssistIntent>(),
            reason: '"$starter" is offered as a button but does not route',
          );
        }
      }
    });
  });
}
