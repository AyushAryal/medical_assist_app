import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/assist_request.dart';
import 'package:medical_app/ai/intent.dart';
import 'package:medical_app/ai/interpreters/patient_interpreter.dart';
import 'package:medical_app/ai/preprocess.dart';
import 'package:medical_app/ai/provenance.dart';

void main() {
  const interpreter = PatientInterpreter();

  Future<AssistIntent?> run(String text, {String? patientId}) {
    final request = AssistRequest(
      text: text,
      source: RequestSource.typed,
      patientId: patientId,
    );
    final input = Preprocessor.run(request, Provenance());
    return interpreter.interpret(request, input);
  }

  test('declines any request that names no patient', () async {
    expect(interpreter.canRead(AssistRequest(
      text: 'how many diabetics',
      source: RequestSource.typed,
    )), isFalse);
    expect(await run('how many diabetics'), isNull);
  });

  test('a resolved patient with no cue is read as a summary', () async {
    final intent = await run('Ramesh Thapa', patientId: 'p1');
    expect(intent, isA<PatientSummaryIntent>());
    final summary = intent! as PatientSummaryIntent;
    expect(summary.patientId, 'p1');
    expect(summary.mode, PatientSummaryMode.summary);
  });

  test('progression wording switches the mode', () async {
    for (final phrasing in <String>[
      'how is Ramesh progressing',
      'is she improving',
      'trend for this patient',
      'how is he doing',
    ]) {
      final intent = await run(phrasing, patientId: 'p1');
      expect((intent! as PatientSummaryIntent).mode,
          PatientSummaryMode.progression,
          reason: phrasing);
    }
  });
}
