import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/summary/referral_letter.dart';
import 'package:medical_app/data/models/allergy.dart';
import 'package:medical_app/data/models/medication.dart';
import 'package:medical_app/data/models/patient.dart';
import 'package:medical_app/data/models/problem.dart';
import 'package:medical_app/data/models/vitals_record.dart';

/// The letter shown when no model is installed (and the floor under whatever
/// a model produces). What it guards: the output must read as a letter — a
/// courteous opening, prose connectives, a close — never the raw field dump
/// it replaced.
void main() {
  final patient = Patient(
    id: 'p1',
    mrn: 'MRN 000001',
    givenName: 'Bimala',
    familyName: 'Shrestha',
    sexAtBirth: SexAtBirth.female,
    dateOfBirth: DateTime(1952, 3, 2),
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  test('reads as a formal letter, not a field dump', () {
    final letter = ReferralLetterComposer.compose(
      patient: patient,
      reason: 'Fever and confusion',
      problems: <Problem>[
        Problem(
          id: 'pr1',
          patientId: 'p1',
          display: 'Type 2 diabetes mellitus',
          status: ProblemStatus.active,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
        Problem(
          id: 'pr2',
          patientId: 'p1',
          display: 'Essential hypertension',
          status: ProblemStatus.active,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
      medications: <Medication>[
        Medication(
          id: 'm1',
          patientId: 'p1',
          name: 'Metformin',
          dose: '500 mg',
          status: MedicationStatus.active,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
      allergies: <Allergy>[
        Allergy(
          id: 'a1',
          patientId: 'p1',
          substance: 'Penicillin',
          reaction: 'Anaphylaxis',
          severity: AllergySeverity.severe,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
    );

    // A letter, in prose.
    expect(letter, startsWith('Thank you for seeing Bimala Shrestha'));
    expect(letter, contains('woman under my care'));
    expect(letter, contains('fever and confusion'));
    expect(letter,
        contains('Type 2 diabetes mellitus and Essential hypertension'));
    expect(letter, contains('Metformin 500 mg'));
    expect(letter, contains('Penicillin allergy (anaphylaxis)'));
    expect(letter, contains('I would value your assessment'));

    // Not the dump it replaced.
    expect(letter, isNot(contains('Referring clinician:')));
    expect(letter, isNot(contains('Problems:')));
    expect(letter, isNot(contains('Medications:')));
  });

  test('says so plainly when nothing is on file', () {
    final letter = ReferralLetterComposer.compose(patient: patient);
    expect(letter, contains('takes no regular medications'));
    expect(letter, contains('no known drug allergies'));
    expect(letter, contains('concerns summarised below'));
  });
}
