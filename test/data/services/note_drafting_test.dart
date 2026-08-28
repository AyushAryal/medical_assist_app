import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/insights/note_sectioniser.dart';
import 'package:medical_app/data/services/assist/note_drafting.dart';

import '../../helpers/scripted_model.dart';

void main() {
  const transcript = 'Patient reports three days of cough and fever. '
      'On examination chest is clear, temperature 37.9. '
      'Likely viral upper respiratory infection. '
      'Paracetamol for fever, review in one week.';

  group('the rules sort a consultation without any model', () {
    test('each sentence lands where clinical wording says it belongs', () {
      final draft = NoteDrafting.sortByRules(transcript);

      expect(draft.sections['subjective'], contains('reports three days'));
      expect(draft.sections['objective'], contains('chest is clear'));
      expect(draft.sections['assessment'], contains('Likely viral'));
      expect(draft.sections['plan'], contains('review in one week'));
      expect(draft.unplaced, isEmpty);
      expect(draft.engineName, rulesEngineName);
    });

    // The property the whole redesign exists for. The previous version asked
    // a model to write the sections and checked afterwards whether it had
    // changed the words; it always had, so the feature never once worked.
    test('every word of every section came from the dictation', () {
      final draft = NoteDrafting.sortByRules(transcript);
      for (final section in draft.sections.values) {
        for (final sentence in NoteSectioniser.sentences(section)) {
          expect(transcript, contains(sentence),
              reason: '"$sentence" is not something the clinician said');
        }
      }
    });

    test('a sentence nothing recognises is left alone, not guessed at', () {
      final draft = NoteDrafting.sortByRules(
        'Patient reports a cough. The weather has been unusual lately.',
      );
      expect(draft.sections['subjective'], contains('reports a cough'));
      expect(draft.unplaced, contains('The weather has been unusual lately.'));
    });

    test('unpunctuated dictation still splits on line breaks', () {
      final draft = NoteDrafting.sortByRules(
        'patient reports headache\non examination pupils equal\n'
        'review in two weeks',
      );
      expect(draft.placed, 3);
    });
  });

  group('the model places what the rules could not', () {
    test('it moves only the undecided sentences, by number', () async {
      const text = 'Patient reports a cough. '
          'Mother is worried about school. '
          'Review in one week.';
      // The middle sentence has no cue; the model is asked about that one and
      // answers with its number, never with text.
      final model = ScriptedModel(assignment: 'SUBJECTIVE: 1');

      final draft = await NoteDrafting.sortWithModel(model, text);
      expect(draft.sections['subjective'], contains('Mother is worried'));
      expect(draft.sections['subjective'], contains('Patient reports a cough'));
      expect(draft.sections['plan'], contains('Review in one week'));
      expect(draft.unplaced, isEmpty);
      // The model saw one numbered sentence — not the whole note.
      expect(model.sawText, '1. Mother is worried about school.');
    });

    // The exact failure that was reported: a small model paraphrases instead
    // of filing. It cannot any more — prose in the reply parses to no numbers.
    test('a model that writes prose changes nothing', () async {
      final model = ScriptedModel(
        assignment: 'The patient has a history of viral URI and is seeking '
            'advice on paracetamol.',
      );
      final draft = await NoteDrafting.sortWithModel(model, transcript);

      final rules = NoteDrafting.sortByRules(transcript);
      expect(draft.sections, rules.sections);
      expect(draft.engineName, rulesEngineName,
          reason: 'the rules did the work, so they get the credit');
    });

    test('a number that does not exist is discarded', () async {
      const text = 'Patient reports a cough. Mother is worried.';
      final model = ScriptedModel(assignment: 'PLAN: 7, 99');
      final draft = await NoteDrafting.sortWithModel(model, text);
      expect(draft.unplaced, contains('Mother is worried.'));
    });

    test('one sentence cannot be filed twice', () async {
      const text = 'Patient reports a cough. Mother is worried.';
      final model = ScriptedModel(assignment: 'PLAN: 1\nOBJECTIVE: 1');
      final draft = await NoteDrafting.sortWithModel(model, text);
      expect(draft.sections['plan'], contains('Mother is worried'));
      expect(draft.sections.containsKey('objective'), isFalse);
    });

    test('a silent model leaves the rules result untouched', () async {
      final draft = await NoteDrafting.sortWithModel(
        ScriptedModel(),
        transcript,
      );
      expect(draft.sections, NoteDrafting.sortByRules(transcript).sections);
    });

    test('provenance marks only the sentence the model filed', () async {
      const text = 'Patient reports a cough. '
          'Mother is worried about school. '
          'Review in one week.';
      final model = ScriptedModel(assignment: 'SUBJECTIVE: 1');
      final draft = await NoteDrafting.sortWithModel(model, text);

      final subjective = draft.provenance['subjective']!;
      final worried =
          subjective.firstWhere((s) => s.text.contains('Mother is worried'));
      final cough =
          subjective.firstWhere((s) => s.text.contains('reports a cough'));
      // The rules read the cough; the model was asked only about the sentence
      // with no cue, and only that one is flagged for a second look.
      expect(worried.placedByModel, isTrue);
      expect(cough.placedByModel, isFalse);
    });

    test('a rules-only sort flags nothing as model-placed', () {
      final draft = NoteDrafting.sortByRules(transcript);
      final flagged = draft.provenance.values
          .expand((s) => s)
          .where((s) => s.placedByModel);
      expect(flagged, isEmpty);
    });
  });

  group('rewording a plan for the patient', () {
    test('a genuine rewording is accepted', () async {
      final model = ScriptedModel(
        instructions: 'Take paracetamol when you have a fever. '
            'Come back to the clinic in one week.',
      );
      final draft = await NoteDrafting.patientInstructions(
        model,
        'Paracetamol PRN for pyrexia. Review 1/52.',
      );
      expect(draft.text, contains('week'));
    });

    test('an echo of the plan is refused', () async {
      const plan = 'Paracetamol PRN for pyrexia. Review 1/52.';
      await expectLater(
        NoteDrafting.patientInstructions(
          ScriptedModel(instructions: plan),
          plan,
        ),
        throwsA(isA<DraftRefused>()),
      );
    });

    test('an essay four times the plan is refused as invention', () async {
      final model = ScriptedModel(instructions: 'Take your medicine. ' * 60);
      await expectLater(
        NoteDrafting.patientInstructions(model, 'Paracetamol PRN.'),
        throwsA(isA<DraftRefused>()),
      );
    });
  });
}
