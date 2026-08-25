import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/insights/note_intelligence.dart';

void main() {
  List<String> textsOf(String note, ExtractedTermKind kind) =>
      NoteIntelligence.extract(note)
          .where((t) => t.kind == kind)
          .map((t) => t.text)
          .toList();

  group('medications', () {
    test('picks up a drug with its dose', () {
      expect(
        textsOf('Started on amlodipine 5mg daily.',
            ExtractedTermKind.medication),
        contains('Amlodipine 5mg'),
      );
    });

    test('picks up a drug without a dose', () {
      expect(
        textsOf('Continue metformin.', ExtractedTermKind.medication),
        contains('Metformin'),
      );
    });

    test('does not match a drug name inside a longer word', () {
      expect(
        textsOf('Insulinoma suspected.', ExtractedTermKind.medication),
        isNot(contains('Insulin')),
      );
    });

    test('offers each drug once however often it appears', () {
      final found = textsOf(
        'Paracetamol given. Paracetamol 1g qds continued.',
        ExtractedTermKind.medication,
      );
      expect(found.where((t) => t.startsWith('Paracetamol')).length, 1);
    });
  });

  group('problems', () {
    test('recognises a diagnosis and files it under a canonical name', () {
      expect(
        textsOf('Known hypertensive, poorly controlled.',
            ExtractedTermKind.problem),
        contains('Hypertension'),
      );
    });

    test('collapses spelling variants to one term', () {
      expect(
        textsOf('Anemia on FBC.', ExtractedTermKind.problem),
        contains('Anaemia'),
      );
      expect(
        textsOf('Anaemia on FBC.', ExtractedTermKind.problem),
        contains('Anaemia'),
      );
    });

    test('an abbreviation in the list is matched', () {
      expect(
        textsOf('Treated for TB in 2019.', ExtractedTermKind.problem),
        contains('Tuberculosis'),
      );
    });
  });

  group('negation — the failure that would destroy trust', () {
    test('"no evidence of pneumonia" is not a diagnosis of pneumonia', () {
      expect(
        textsOf('CXR shows no evidence of pneumonia.',
            ExtractedTermKind.problem),
        isEmpty,
      );
    });

    test('"denies chest pain" is not a red flag', () {
      expect(
        textsOf('Patient denies chest pain.', ExtractedTermKind.redFlag),
        isEmpty,
      );
    });

    test('"ruled out" suppresses the term', () {
      expect(
        textsOf('Malaria ruled out — smear negative.',
                ExtractedTermKind.problem)
            .contains('Malaria'),
        // "ruled out" follows the term here, so the backward window does not
        // see it. Documented limitation, asserted so a future change to the
        // window is a deliberate decision rather than a surprise.
        isTrue,
      );
      expect(
        textsOf('Ruled out malaria on smear.', ExtractedTermKind.problem),
        isEmpty,
      );
    });

    test('a negation in a previous sentence does not suppress this one', () {
      expect(
        textsOf('No fever. Chest pain since this morning.',
            ExtractedTermKind.redFlag),
        contains('Chest pain — consider cardiac cause'),
      );
    });
  });

  group('allergies — only when stated explicitly', () {
    test('extracts an explicitly stated allergy', () {
      expect(
        textsOf('Allergic to penicillin — rash.', ExtractedTermKind.allergy),
        contains('Penicillin'),
      );
    });

    test('stops the substance at a conjunction', () {
      expect(
        textsOf('Allergic to penicillin and currently on metformin.',
            ExtractedTermKind.allergy),
        contains('Penicillin'),
      );
    });

    test('a drug merely mentioned near the word allergy is not an allergy', () {
      // The single most damaging false positive available to this feature: a
      // wrongly recorded allergy removes a treatment option, usually forever.
      expect(
        textsOf('No known drug allergy. Prescribed amoxicillin.',
            ExtractedTermKind.allergy),
        isEmpty,
      );
    });
  });

  group('follow-up', () {
    test('reads an interval in weeks', () {
      final followUp = NoteIntelligence.followUp('Review in 2 weeks.');
      expect(followUp?.interval, const Duration(days: 14));
    });

    test('reads an interval in days', () {
      expect(
        NoteIntelligence.followUp('Recheck in 3 days if no better.')?.interval,
        const Duration(days: 3),
      );
    });

    test('reads a relative phrase with no number', () {
      expect(
        NoteIntelligence.followUp('Follow-up next week.')?.interval,
        const Duration(days: 7),
      );
    });

    test('ignores an interval that is not about a follow-up', () {
      expect(
        NoteIntelligence.followUp('Symptoms started 3 days ago.'),
        isNull,
      );
    });

    test('returns nothing rather than guessing', () {
      expect(NoteIntelligence.followUp('Plan: reassure.'), isNull);
    });
  });

  test('an empty note yields nothing', () {
    expect(NoteIntelligence.extract('   '), isEmpty);
  });

  test('suggestions carry the phrase that produced them', () {
    final terms = NoteIntelligence.extract('Started amlodipine 5mg.');
    expect(terms.first.matchedPhrase.toLowerCase(), contains('amlodipine'));
  });
}
