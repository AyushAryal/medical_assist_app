import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/data/services/assist/note_drafting.dart';

import '../../helpers/scripted_model.dart';

void main() {
  const transcript = 'Patient reports three days of cough and fever. '
      'Chest clear on auscultation, temperature 37.9. '
      'Likely viral upper respiratory infection. '
      'Paracetamol for fever, review in one week.';

  group('sorting a dictation into SOAP', () {
    test('a faithful sort is accepted, empty sections dropped', () async {
      final model = ScriptedModel(soap: <String, String>{
        'subjective': 'Patient reports three days of cough and fever.',
        'objective': 'Chest clear on auscultation, temperature 37.9.',
        'assessment': 'Likely viral upper respiratory infection.',
        'plan': 'Paracetamol for fever, review in one week.',
      });

      final draft = await NoteDrafting.sortIntoSoap(model, transcript);
      expect(draft.sections.keys,
          containsAll(<String>['subjective', 'objective', 'plan']));
    });

    // The failure that makes the gate worth having: the "sort" quietly edits
    // the record. A new drug, a new number, a new negation all look tidy and
    // are all corruption.
    test('invented words are refused, and named', () async {
      final model = ScriptedModel(soap: <String, String>{
        'subjective': 'Patient reports three days of cough and fever. '
            'Chest clear on auscultation, temperature 37.9. '
            'Likely viral upper respiratory infection.',
        'plan': 'Amoxicillin for fever, review in one week.',
      });

      await expectLater(
        NoteDrafting.sortIntoSoap(model, transcript),
        throwsA(
          isA<DraftRefused>().having(
            (e) => e.reason,
            'reason',
            contains('amoxicillin'),
          ),
        ),
      );
    });

    test('dropping most of the dictation is refused', () async {
      final model = ScriptedModel(soap: <String, String>{
        'subjective': 'Patient reports cough.',
      });
      await expectLater(
        NoteDrafting.sortIntoSoap(model, transcript),
        throwsA(isA<DraftRefused>()),
      );
    });

    test('a model that returns no sections is refused', () async {
      await expectLater(
        NoteDrafting.sortIntoSoap(ScriptedModel(), transcript),
        throwsA(isA<DraftRefused>()),
      );
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
