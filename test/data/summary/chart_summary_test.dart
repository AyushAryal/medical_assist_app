import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/news2.dart';
import 'package:medical_app/clinical/summary/record_summary.dart';
import 'package:medical_app/data/models/allergy.dart';
import 'package:medical_app/data/models/medication.dart';
import 'package:medical_app/data/models/patient.dart';
import 'package:medical_app/data/models/problem.dart';
import 'package:medical_app/data/models/vitals_record.dart';
import 'package:medical_app/data/summary/chart_summary.dart';

void main() {
  final asOf = DateTime(2026, 8, 29, 10, 0);
  final epoch = DateTime(2026, 1, 1);

  Patient patient({
    AllergyStatus allergyStatus = AllergyStatus.unknown,
    DateTime? lastSeen,
    DateTime? dob,
  }) =>
      Patient(
        id: 'p',
        mrn: '001',
        familyName: 'Doe',
        givenName: 'Jane',
        allergyStatus: allergyStatus,
        dateOfBirth: dob ?? DateTime(1980),
        lastSeenAt: lastSeen,
        createdAt: epoch,
        updatedAt: epoch,
      );

  SummaryItem itemIn(RecordSummary s, String key) =>
      s.sections.firstWhere((sec) => sec.key == key).items.single;

  test('an unknown allergy status maps to a not-recorded gap', () {
    final s = ChartSummary.build(
      patient: patient(allergyStatus: AllergyStatus.unknown),
      allergies: const [],
      activeProblems: const [],
      activeMedications: const [],
      latestVitals: null,
      asOf: asOf,
    );
    expect(itemIn(s, 'allergies').state, SummaryState.notRecorded);
  });

  test('active allergies are listed; inactive ones are dropped', () {
    final s = ChartSummary.build(
      patient: patient(allergyStatus: AllergyStatus.hasAllergies),
      allergies: <Allergy>[
        Allergy(
          id: 'a1',
          patientId: 'p',
          substance: 'Penicillin',
          severity: AllergySeverity.anaphylaxis,
          status: AllergyRecordStatus.active,
          createdAt: epoch,
          updatedAt: epoch,
        ),
        Allergy(
          id: 'a2',
          patientId: 'p',
          substance: 'Old entry',
          severity: AllergySeverity.mild,
          status: AllergyRecordStatus.refuted,
          createdAt: epoch,
          updatedAt: epoch,
        ),
      ],
      activeProblems: const [],
      activeMedications: const [],
      latestVitals: null,
      asOf: asOf,
    );
    final item = itemIn(s, 'allergies');
    expect(item.value, contains('Penicillin'));
    expect(item.value, isNot(contains('Old entry')));
    expect(item.severity, isNotNull); // anaphylaxis -> a tone
  });

  test('problems and medications flatten to their display text', () {
    final s = ChartSummary.build(
      patient: patient(allergyStatus: AllergyStatus.noKnownAllergies),
      allergies: const [],
      activeProblems: <Problem>[
        Problem(
          id: 'pr1',
          patientId: 'p',
          display: 'Hypertension',
          createdAt: epoch,
          updatedAt: epoch,
        ),
      ],
      activeMedications: <Medication>[
        Medication(
          id: 'md1',
          patientId: 'p',
          name: 'Amlodipine',
          dose: '5',
          doseUnit: 'mg',
          createdAt: epoch,
          updatedAt: epoch,
        ),
      ],
      latestVitals: null,
      asOf: asOf,
    );
    expect(itemIn(s, 'problems').value, 'Hypertension');
    expect(itemIn(s, 'medications').value, 'Amlodipine 5 mg');
  });

  test('the latest vitals are scored through the shared calculator', () {
    final s = ChartSummary.build(
      patient: patient(allergyStatus: AllergyStatus.noKnownAllergies),
      allergies: const [],
      activeProblems: const [],
      activeMedications: const [],
      latestVitals: VitalsRecord(
        id: 'v1',
        patientId: 'p',
        recordedAt: DateTime(2026, 8, 29, 9, 5),
        respiratoryRate: 28,
        spo2: 91,
        onOxygen: true,
        systolicBp: 100,
        heartRate: 120,
        consciousness: Consciousness.alert,
        temperatureC: 37,
        createdAt: epoch,
        updatedAt: epoch,
      ),
      asOf: asOf,
    );
    final item = itemIn(s, 'observations');
    expect(item.state, SummaryState.recorded);
    expect(item.value, startsWith('NEWS2'));
    expect(item.value, contains('High'));
  });

  test('lastSeenAt drives the activity line', () {
    final s = ChartSummary.build(
      patient: patient(
        allergyStatus: AllergyStatus.noKnownAllergies,
        lastSeen: DateTime(2026, 8, 20),
      ),
      allergies: const [],
      activeProblems: const [],
      activeMedications: const [],
      latestVitals: null,
      asOf: asOf,
    );
    final item = itemIn(s, 'activity');
    expect(item.value, '2026-08-20');
    expect(item.state, SummaryState.recorded);
  });
}
