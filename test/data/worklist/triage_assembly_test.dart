import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/news2.dart';
import 'package:medical_app/data/models/appointment.dart';
import 'package:medical_app/data/models/patient.dart';
import 'package:medical_app/data/models/vitals_record.dart';
import 'package:medical_app/data/worklist/triage_assembly.dart';

/// The assembly is the join between stored rows and the pure triage rule, so
/// its mapping choices (which age, which timestamp, what a missing vitals row
/// means) are pinned here.
void main() {
  final asOf = DateTime(2026, 8, 29, 10, 0);
  final epoch = DateTime(2026, 1, 1);

  Patient patient({
    required String id,
    required String mrn,
    DateTime? dob,
  }) =>
      Patient(
        id: id,
        mrn: mrn,
        familyName: 'Test',
        givenName: id,
        dateOfBirth: dob,
        createdAt: epoch,
        updatedAt: epoch,
      );

  Appointment arrived({
    required String patientId,
    DateTime? arrivedAt,
  }) =>
      Appointment(
        id: 'appt-$patientId',
        patientId: patientId,
        clinicId: 'c1',
        scheduledAt: asOf.subtract(const Duration(hours: 1)),
        status: AppointmentStatus.arrived,
        arrivedAt: arrivedAt,
        createdAt: epoch,
        updatedAt: epoch,
      );

  VitalsRecord vitals({
    required String patientId,
    required DateTime recordedAt,
    int? rr,
    int? spo2,
    int? sbp,
    int? hr,
    Consciousness? loc,
    double? temp,
  }) =>
      VitalsRecord(
        id: 'v-$patientId',
        patientId: patientId,
        recordedAt: recordedAt,
        respiratoryRate: rr,
        spo2: spo2,
        systolicBp: sbp,
        heartRate: hr,
        consciousness: loc,
        temperatureC: temp,
        createdAt: epoch,
        updatedAt: epoch,
      );

  test('uses arrivedAt as the wait anchor', () {
    final model = TriageAssembly.build(asOf: asOf, records: [
      (
        appointment: arrived(
          patientId: 'p',
          arrivedAt: asOf.subtract(const Duration(minutes: 25)),
        ),
        patient: patient(id: 'p', mrn: '001', dob: DateTime(1980)),
        latestVitals: null,
      ),
    ]);
    expect(model.subjects.single.arrivedAt,
        asOf.subtract(const Duration(minutes: 25)));
  });

  test('falls back to the slot time when arrivedAt is missing', () {
    final appt = arrived(patientId: 'p', arrivedAt: null);
    final model = TriageAssembly.build(asOf: asOf, records: [
      (
        appointment: appt,
        patient: patient(id: 'p', mrn: '001', dob: DateTime(1980)),
        latestVitals: null,
      ),
    ]);
    expect(model.subjects.single.arrivedAt, appt.scheduledAt);
  });

  test('a patient with no vitals row is unknown risk, not scored', () {
    final model = TriageAssembly.build(asOf: asOf, records: [
      (
        appointment: arrived(patientId: 'p'),
        patient: patient(id: 'p', mrn: '001', dob: DateTime(1980)),
        latestVitals: null,
      ),
    ]);
    final s = model.subjects.single;
    expect(s.isScored, isFalse);
    expect(s.unavailableReason, News2Unavailable.incompleteObservations);
  });

  test('a child is out of NEWS2 scope from their date of birth', () {
    final model = TriageAssembly.build(asOf: asOf, records: [
      (
        appointment: arrived(patientId: 'p'),
        patient: patient(id: 'p', mrn: '001', dob: DateTime(2019)), // age 7
        latestVitals: vitals(
          patientId: 'p',
          recordedAt: asOf,
          rr: 20,
          spo2: 98,
          sbp: 110,
          hr: 90,
          loc: Consciousness.alert,
          temp: 37,
        ),
      ),
    ]);
    final s = model.subjects.single;
    expect(s.isScored, isFalse);
    expect(s.unavailableReason, News2Unavailable.ageOutOfScope);
  });

  test('a complete adult observation set scores, carrying the vitals row id', () {
    final model = TriageAssembly.build(asOf: asOf, records: [
      (
        appointment: arrived(patientId: 'p'),
        patient: patient(id: 'p', mrn: '001', dob: DateTime(1980)),
        latestVitals: vitals(
          patientId: 'p',
          recordedAt: asOf.subtract(const Duration(minutes: 5)),
          rr: 22, // 2
          spo2: 94, // 1
          sbp: 108, // 1
          hr: 95, // 1
          loc: Consciousness.alert,
          temp: 38.5, // 1
        ),
      ),
    ]);
    final s = model.subjects.single;
    expect(s.isScored, isTrue);
    expect(s.news2Total, 6);
    expect(s.risk, News2Risk.medium);
    expect(s.vitalsRecordId, 'v-p');
    expect(s.vitalsRecordedAt, asOf.subtract(const Duration(minutes: 5)));
  });
}
