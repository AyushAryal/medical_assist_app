import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/data/models/encounter.dart';
import 'package:medical_app/data/models/patient.dart';
import 'package:medical_app/data/worklist/recall_assembly.dart';

void main() {
  final asOf = DateTime(2026, 8, 29);
  final epoch = DateTime(2026, 1, 1);

  Patient patient(String id) => Patient(
        id: id,
        mrn: 'MRN-$id',
        familyName: 'Test',
        givenName: id,
        createdAt: epoch,
        updatedAt: epoch,
      );

  Encounter encounter({
    required String patientId,
    required DateTime startedAt,
    DateTime? followUpDate,
    String? complaint,
  }) =>
      Encounter(
        id: 'e-$patientId-${startedAt.millisecondsSinceEpoch}',
        patientId: patientId,
        clinicId: 'c1',
        startedAt: startedAt,
        followUpDate: followUpDate,
        chiefComplaint: complaint,
        createdAt: epoch,
        updatedAt: epoch,
      );

  test('a passed follow-up on the latest visit makes the patient due', () {
    final model = RecallAssembly.build(asOf: asOf, records: [
      (
        patient: patient('a'),
        encounters: [
          encounter(
            patientId: 'a',
            startedAt: DateTime(2026, 8, 1),
            followUpDate: DateTime(2026, 8, 15),
            complaint: 'BP review',
          ),
        ],
      ),
    ]);
    final s = model.subjects.single;
    expect(s.patientId, 'a');
    expect(s.dueDate, DateTime(2026, 8, 15));
    expect(s.reason, 'BP review');
  });

  test('a later visit since the review clears the recall', () {
    final model = RecallAssembly.build(asOf: asOf, records: [
      (
        patient: patient('a'),
        encounters: [
          encounter(
            patientId: 'a',
            startedAt: DateTime(2026, 8, 1),
            followUpDate: DateTime(2026, 8, 15),
          ),
          // Seen again after the review was due; the newer visit set no
          // follow-up, so nothing is outstanding.
          encounter(patientId: 'a', startedAt: DateTime(2026, 8, 20)),
        ],
      ),
    ]);
    expect(model.subjects, isEmpty);
  });

  test('a future follow-up is not yet due', () {
    final model = RecallAssembly.build(asOf: asOf, records: [
      (
        patient: patient('a'),
        encounters: [
          encounter(
            patientId: 'a',
            startedAt: DateTime(2026, 8, 1),
            followUpDate: DateTime(2026, 9, 30),
          ),
        ],
      ),
    ]);
    expect(model.subjects, isEmpty);
  });

  test('the most recent visit governs when it carries the newer plan', () {
    final model = RecallAssembly.build(asOf: asOf, records: [
      (
        patient: patient('a'),
        encounters: [
          encounter(
            patientId: 'a',
            startedAt: DateTime(2026, 7, 1),
            followUpDate: DateTime(2026, 7, 20),
          ),
          encounter(
            patientId: 'a',
            startedAt: DateTime(2026, 8, 1),
            followUpDate: DateTime(2026, 8, 10),
            complaint: 'Diabetes review',
          ),
        ],
      ),
    ]);
    final s = model.subjects.single;
    expect(s.dueDate, DateTime(2026, 8, 10));
    expect(s.reason, 'Diabetes review');
  });

  test('a patient with no encounters is skipped', () {
    final model = RecallAssembly.build(asOf: asOf, records: [
      (patient: patient('a'), encounters: const <Encounter>[]),
    ]);
    expect(model.subjects, isEmpty);
  });
}
