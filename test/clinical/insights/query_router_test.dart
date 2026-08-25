import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/cohort/cohort_query.dart';
import 'package:medical_app/ai/cohort/query_router.dart';

void main() {
  final now = DateTime(2026, 8, 24);

  RoutedQuery? route(String q) => QueryRouter.route(q, asOf: now);

  group('safety recall lists', () {
    test('finds a medicine and asks for a list, not a count', () {
      final routed = route('everyone on warfarin')!;

      expect(routed.query.medication, 'warfarin');
      expect(routed.query.kind, CohortQueryKind.recall);
      expect(routed.query.kind.listsPatients, isTrue);
    });

    test('an allergy phrasing produces an allergy filter, not a drug list', () {
      // The distinction matters: "on penicillin" and "allergic to penicillin"
      // are opposite cohorts, and confusing them during a recall would be
      // actively dangerous.
      final routed = route('patients allergic to penicillin')!;

      expect(routed.query.allergy, 'penicillin');
      expect(routed.query.medication, isNull);
    });

    test('"on" a drug is a medication filter', () {
      final routed = route('list patients on metformin')!;

      expect(routed.query.medication, 'metformin');
      expect(routed.query.allergy, isNull);
    });
  });

  group('overdue follow-up', () {
    test('reads a condition and an interval', () {
      final routed = route('diabetics not seen in 6 months')!;

      expect(routed.query.problem, 'Diabetes mellitus');
      expect(routed.query.kind, CohortQueryKind.overdue);
      expect(routed.query.notSeenSince, DateTime(2026, 2, 24));
    });

    test('bare "overdue" assumes six months and says so', () {
      final routed = route('hypertensive patients overdue for review')!;

      expect(routed.query.problem, 'Hypertension');
      expect(routed.query.notSeenSince, DateTime(2026, 2, 24));
      expect(routed.matched.join(' '), contains('assumed'));
    });

    test('an overdue query is never silently turned into a count', () {
      expect(route('asthma patients not seen in 12 months')!.query.kind,
          CohortQueryKind.overdue);
    });
  });

  group('clinic activity', () {
    test('"how many" asks for a count', () {
      final routed = route('how many patients did we see last month')!;

      expect(routed.query.kind, CohortQueryKind.activity);
      expect(routed.query.kind.listsPatients, isFalse);
      expect(routed.query.periodFrom, DateTime(2026, 7, 1));
      expect(routed.query.periodTo, DateTime(2026, 8, 1));
    });

    test('resolves this month', () {
      final routed = route('how many seen this month')!;
      expect(routed.query.periodFrom, DateTime(2026, 8, 1));
      expect(routed.query.periodTo, DateTime(2026, 9, 1));
    });

    test('resolves a rolling window', () {
      final routed = route('how many patients in the last 30 days')!;
      expect(routed.query.periodFrom, DateTime(2026, 7, 25));
    });

    test('resolves this week from Monday', () {
      // 24 Aug 2026 is a Monday, so this week starts that day.
      final routed = route('how many did we see this week')!;
      expect(routed.query.periodFrom, DateTime(2026, 8, 24));
    });
  });

  group('cohort counts', () {
    test('combines age band, condition and period', () {
      final routed = route('under fives with pneumonia this month')!;

      expect(routed.query.ageBand, AgeBand.under5);
      expect(routed.query.problem, 'Pneumonia');
      expect(routed.query.periodFrom, DateTime(2026, 8, 1));
    });

    test('reads sex', () {
      expect(route('female patients with anaemia')!.query.sexAtBirth, 'female');
      expect(route('male patients with anaemia')!.query.sexAtBirth, 'male');
    });

    test('recognises the age words clinicians actually use', () {
      expect(route('infants with pneumonia')!.query.ageBand, AgeBand.under1);
      expect(route('children with asthma')!.query.ageBand, AgeBand.child);
      expect(route('elderly patients on warfarin')!.query.ageBand,
          AgeBand.over65);
    });
  });

  group('refuses rather than guesses', () {
    test('an unrecognised question falls back to searching the prose', () {
      // The contract changed deliberately. Refusing anything outside a fixed
      // vocabulary makes the search useless for the half of clinical
      // information that only ever exists as prose — a word like "coffee" is
      // never going to be a structured field, and is perfectly reasonable to
      // look for. So an unmatched question searches the text instead, and the
      // result is labelled as an inexact match rather than presented as an
      // answer.
      final routed = route('what is the weather like')!;

      expect(routed.query.anyTextOf, contains('weather'));
      expect(
        routed.query.anyTextOf,
        isNot(contains('what')),
        reason: 'words that would match everything are dropped',
      );
    });

    test('a question with no searchable words at all still returns null', () {
      // The floor: if nothing survives stop-word removal there is nothing to
      // search for, and inventing a query would be worse than saying so.
      expect(route('the and or of'), isNull);
      expect(route('?!'), isNull);
    });

    test('an empty question returns null', () {
      expect(route(''), isNull);
      expect(route('   '), isNull);
    });

    test('a thin match is reported with low confidence', () {
      final routed = route(
        'can you please have a look and tell me about the warfarin situation '
        'across the whole clinic thanks',
      )!;
      expect(routed.confidence, lessThan(0.6));
    });

    test('a tight match is reported with high confidence', () {
      expect(route('everyone on warfarin')!.confidence, greaterThan(0.6));
    });
  });

  test('every filter it applies is reported back', () {
    final routed = route('under fives with pneumonia this month')!;

    expect(routed.matched, hasLength(3));
    // The description is what makes a misread question visible on screen.
    final described = routed.query.describe().join(' ');
    expect(described, contains('Pneumonia'));
    expect(described, contains('under 5'));
  });

  test('deceased patients are excluded unless asked for', () {
    // A recall list that telephones the dead is not a data problem.
    expect(route('everyone on warfarin')!.query.includeDeceased, isFalse);
    expect(
      route('everyone on warfarin')!.query.describe().join(' '),
      contains('Excluding patients recorded as deceased'),
    );
  });

  group('names — the front-desk questions', () {
    test('name starting with a letter', () {
      final routed = route('patients with name starting with A')!;
      expect(routed.query.nameStartsWith, 'A');
      expect(routed.query.entity, QueryEntity.patients);
    });

    test('"names beginning with" is the same question', () {
      expect(route('names beginning with Ar')!.query.nameStartsWith, 'Ar');
    });

    test('a bare initial after "surname with"', () {
      expect(route('surname with A')!.query.nameStartsWith, 'A');
    });

    test('"called X" searches for a name containing X', () {
      final routed = route('patients called Sita')!;
      expect(routed.query.nameContains, 'Sita');
      expect(routed.query.nameStartsWith, isNull);
    });

    test('"surname Aryal" is a name search', () {
      expect(route('surname Aryal')!.query.nameContains, 'Aryal');
    });

    test('an MRN is read exactly', () {
      expect(route('mrn 004512')!.query.mrn, '004512');
      expect(route('record number 004512')!.query.mrn, '004512');
    });
  });

  group('appointments — a different table from visits', () {
    test('"appointments this month" selects the appointments table', () {
      final routed = route('appointments this month')!;

      expect(routed.query.entity, QueryEntity.appointments);
      expect(routed.query.periodFrom, DateTime(2026, 8, 1));
      expect(routed.query.periodTo, DateTime(2026, 9, 1));
      // A bare period on a non-patient table is a "how many" question.
      expect(routed.query.kind, CohortQueryKind.activity);
    });

    test('"visits last month" selects visits, not appointments', () {
      // Booked and happened are different numbers, and a clinic with many
      // non-attenders has very different values for the two.
      final routed = route('how many visits last month')!;
      expect(routed.query.entity, QueryEntity.visits);
    });

    test('reads a cancellation', () {
      final routed = route('appointments that were cancelled this month')!;
      expect(routed.query.entity, QueryEntity.appointments);
      expect(routed.query.appointmentStatus, 'cancelled');
    });

    test('reads non-attendance in the several ways it is said', () {
      for (final phrase in <String>[
        'appointments where the patient did not attend',
        'no shows this month',
        'appointment dna last week',
      ]) {
        expect(
          route(phrase)?.query.appointmentStatus,
          'noShow',
          reason: phrase,
        );
      }
    });

    test('bookings are appointments', () {
      expect(route('bookings next week')?.query.entity,
          QueryEntity.appointments);
    });

    test('a patient filter combines with an appointment question', () {
      final routed = route('diabetics with appointments this week')!;
      expect(routed.query.entity, QueryEntity.appointments);
      expect(routed.query.problem, 'Diabetes mellitus');
      expect(routed.query.periodFrom, DateTime(2026, 8, 24));
    });

    test('"missed appointments" is a status, not an overdue patient list', () {
      // "missed" alone is ambiguous — a missed appointment is a booking
      // status, a missed review is an overdue patient.
      final routed = route('missed appointments this month')!;
      expect(routed.query.entity, QueryEntity.appointments);
      expect(routed.query.appointmentStatus, 'noShow');
      expect(routed.query.kind, isNot(CohortQueryKind.overdue));
    });

    test('"missed their review" is still an overdue patient list', () {
      expect(
        route('diabetics who missed their review')!.query.kind,
        CohortQueryKind.overdue,
      );
    });
  });

  test('defaults to the patient register when no table is named', () {
    expect(route('everyone on warfarin')!.query.entity, QueryEntity.patients);
  });

  test('every table trigger word the guide advertises actually works', () {
    // The guide and the router read the same list. This asserts they cannot
    // drift: a phrase the app teaches is a phrase it understands.
    for (final entity in QueryEntity.values) {
      for (final word in entity.triggerWords) {
        final routed = route('$word this month');
        expect(routed, isNotNull, reason: '"$word" did not route');
        expect(routed!.query.entity, entity, reason: '"$word" chose the wrong table');
      }
    }
  });

  group('the words people actually type', () {
    test('"all patients" and "every single patient" are the same request', () {
      for (final phrase in <String>[
        'all patients',
        'every single patient',
        'every patient',
        'show me all the patients',
        'can you list all patients please',
        'everyone',
      ]) {
        final routed = route(phrase);
        expect(routed, isNotNull, reason: phrase);
        expect(routed!.query.entity, QueryEntity.patients, reason: phrase);
        expect(routed.query.isEmpty, isTrue,
            reason: '$phrase should carry no filters');
        expect(routed.query.kind.listsPatients, isTrue, reason: phrase);
      }
    });

    test('"how many patients" counts rather than lists', () {
      final routed = route('how many patients are there in total')!;
      expect(routed.query.kind, CohortQueryKind.activity);
    });

    test('"all appointments" selects the appointments table', () {
      expect(route('all appointments')?.query.entity,
          QueryEntity.appointments);
    });

    test('politeness does not change the meaning', () {
      final plain = route('everyone on warfarin')!;
      final polite = route('Could you please show me everyone on warfarin?')!;

      expect(polite.query.medication, plain.query.medication);
      expect(polite.query.entity, plain.query.entity);
    });

    test('punctuation is tolerated', () {
      expect(route('appointments this month?')?.query.entity,
          QueryEntity.appointments);
    });

    test('a quantifier does not silently return the whole register', () {
      // Deciding "whole table" by subtraction rather than by spotting "all" is
      // what stops these returning every patient. They fall through to a prose
      // search, which is a much smaller and more honest claim.
      final weather = route('all the weather')!;
      expect(weather.query.anyTextOf, contains('weather'));
      expect(weather.query.mostRecent, isNull);

      final moon = route('every single thing about the moon')!;
      expect(moon.query.anyTextOf, contains('moon'));
    });
  });

  group('a question that matched nothing structured', () {
    test('is marked as text-only', () {
      // The distinction is load-bearing. A query with no structured filter
      // matches *everything*, so answering one by counting patients reports
      // the whole register — "hello" came back as "13 patients found", which
      // is both wrong and confidently stated.
      final routed = route('hell hello')!;

      expect(routed.query.isTextOnly, isTrue);
      expect(routed.query.anyTextOf, isNotEmpty);
    });

    test('a real filter is not text-only', () {
      expect(route('everyone on warfarin')!.query.isTextOnly, isFalse);
      expect(route('appointments this month')!.query.isTextOnly, isFalse);
      expect(route('latest patients')!.query.isTextOnly, isFalse);
    });

    test('text terms alongside a filter are not text-only', () {
      final routed = route('diabetics mentioning coffee')!;
      expect(routed.query.problem, 'Diabetes mellitus');
      expect(routed.query.isTextOnly, isFalse);
    });

    test('"all patients" is not text-only — it is the whole table', () {
      final routed = route('all patients')!;
      expect(routed.query.isTextOnly, isFalse);
      expect(routed.query.anyTextOf, isEmpty);
    });
  });

  group('recency', () {
    test('"latest patients" is understood', () {
      // Ordinary phrasing that produced nothing at all before, because the
      // vocabulary was built around filters with no way to express "newest".
      final routed = route('latest patients')!;
      expect(routed.query.mostRecent, isNotNull);
      expect(routed.query.entity, QueryEntity.patients);
    });

    test('a count is read when one is given', () {
      expect(route('last 5 visits')!.query.mostRecent, 5);
      expect(route('most recent 20 notes')!.query.mostRecent, 20);
    });

    test('recency combines with a table', () {
      final routed = route('latest appointments')!;
      expect(routed.query.entity, QueryEntity.appointments);
      expect(routed.query.mostRecent, isNotNull);
    });
  });

  group('free text', () {
    test('several terms are all searched', () {
      final routed = route('entries with coffee or tea')!;
      expect(routed.query.anyTextOf, containsAll(<String>['coffee', 'tea']));
    });

    test('a quoted phrase is taken literally and alone', () {
      final routed = route('notes mentioning "chest tightness"')!;
      expect(routed.query.anyTextOf, <String>['chest tightness']);
    });

    test('a structured match is preferred over a text search', () {
      // "warfarin" is a medicine the app knows, so it becomes a real filter
      // rather than a word to grep for.
      final routed = route('everyone on warfarin')!;
      expect(routed.query.medication, 'warfarin');
      expect(routed.query.anyTextOf, isEmpty);
    });
  });

  test('every advertised example actually routes', () {
    // The empty state offers these. Suggesting a question the app cannot
    // answer is worse than offering nothing.
    for (final example in QueryRouter.examples) {
      expect(
        route(example),
        isNotNull,
        reason: 'example "$example" does not route',
      );
    }
  });
}
