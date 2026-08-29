import 'package:flutter_test/flutter_test.dart';

import '../../helpers/scripted_model.dart';

/// Every AI feature is a *rewriting* task: the model is handed structured text
/// the app built and returns a marked draft. These pin that shape for the
/// summary brief, the recall reminder and the triage talking points.
void main() {
  test('spokenBrief is handed the structured summary', () async {
    final model = ScriptedModel(rewrite: 'A brief.');
    final draft = await model.spokenBrief('Allergies: No known allergies');
    expect(model.sawText, 'Allergies: No known allergies');
    expect(draft.text, 'A brief.');
    expect(draft.engineName, 'scripted-test-model');
  });

  test('patientReminder is handed the review facts', () async {
    final model = ScriptedModel(rewrite: 'Hi, please book your review.');
    final draft =
        await model.patientReminder('Patient: Jane. Review due 2026-08-15.');
    expect(model.sawText, contains('Review due 2026-08-15'));
    expect(draft.text, 'Hi, please book your review.');
  });

  test('triageTalkingPoints is handed the presentation', () async {
    final model = ScriptedModel(rewrite: 'Ask about onset.');
    final draft = await model.triageTalkingPoints('Patient: Ram. Red flag: chest pain');
    expect(model.sawText, contains('chest pain'));
    expect(draft.text, 'Ask about onset.');
  });
}
