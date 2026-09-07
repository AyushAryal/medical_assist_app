import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/summary/handoff.dart';
import 'package:medical_app/clinical/summary/record_summary.dart';
import 'package:medical_app/clinical/summary/summary_builder.dart';

import '../../helpers/scripted_model.dart';

/// The AI read-aloud handoff is a *rewriting* of the deterministic handoff:
/// the model is handed the structured SBAR the app built, never the raw
/// record, and its output is a marked draft — never the source of truth.
void main() {
  final asOf = DateTime(2026, 8, 29, 10, 0);

  Handoff buildHandoff() {
    final record = SummaryBuilder.build(ChartSnapshot(
      patientId: 'p',
      asOf: asOf,
      allergyState: AllergyRecordState.noneKnown,
      activeProblems: const ['Hypertension'],
      currentMedications: const ['Amlodipine 5 mg'],
      lastEncounterAt: DateTime(2026, 8, 1),
    ));
    return HandoffBuilder.build(HandoffInput(
      patientId: 'p',
      asOf: asOf,
      identityLine: 'Jane Doe · 46y · F · MRN 001',
      record: record,
      presentingComplaint: 'chest pain',
    ));
  }

  test('the model rewords the structured handoff, not the raw record', () async {
    final model = ScriptedModel(handoff: 'Jane Doe, 46, here with chest pain…');
    final handoff = buildHandoff();

    final draft = await model.spokenHandoff(handoff.plainText);

    // It was handed the deterministic SBAR text.
    expect(model.sawText, handoff.plainText);
    expect(model.sawText, contains('S — Situation'));
    // And returns a marked draft carrying the engine name.
    expect(draft.text, 'Jane Doe, 46, here with chest pain…');
    expect(draft.engineName, 'scripted-test-model');
  });

  test('the structured handoff remains valid on its own', () {
    // The deterministic handoff never depends on the model existing.
    final handoff = buildHandoff();
    expect(handoff.plainText, contains('R — Recommendation'));
  });
}
