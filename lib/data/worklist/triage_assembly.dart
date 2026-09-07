import '../../clinical/flags/clinical_flag.dart';
import '../../clinical/flags/red_flag_rule.dart';
import '../../clinical/patient_age.dart';
import '../../clinical/worklist/triage_worklist.dart';
import '../models/appointment.dart';
import '../models/patient.dart';
import '../models/vitals_record.dart';

/// One waiting patient's records, gathered for triage.
typedef TriageRecord = ({
  Appointment appointment,
  Patient patient,
  VitalsRecord? latestVitals,
});

/// Maps stored records into the clinical layer's [TriageReadModel].
///
/// Deliberately pure: it takes model objects, not a database, so the mapping
/// — which age we pass to NEWS2, which timestamp counts as arrival, what a
/// missing vitals row means — is unit-tested with fixtures rather than behind
/// I/O. The DB-backed builder is the thin part that fetches rows and calls
/// this.
abstract final class TriageAssembly {
  static TriageReadModel build({
    required DateTime asOf,
    required Iterable<TriageRecord> records,
  }) {
    final subjects = <TriageSubject>[
      for (final r in records) _subjectOf(r, asOf),
    ];
    return TriageReadModel(asOf: asOf, subjects: subjects);
  }

  static TriageSubject _subjectOf(TriageRecord r, DateTime asOf) {
    final patient = r.patient;
    final vitals = r.latestVitals;
    final age = PatientAge.fromDateOfBirth(patient.dateOfBirth, asOf: asOf);

    return TriageSubject.fromObservations(
      patientId: patient.id,
      mrn: patient.mrn,
      displayName: patient.displayName,
      // An arrived appointment carries arrivedAt; fall back to the slot time so
      // a mis-recorded arrival still places the patient rather than crashing.
      arrivedAt: r.appointment.arrivedAt ?? r.appointment.scheduledAt,
      ageYears: age?.years,
      // Pregnancy is not modelled on the patient record yet, so NEWS2 is left
      // to refuse only on age. When a pregnancy flag is added this is where it
      // feeds in — until then the board must not imply a pregnant patient was
      // scored, which the "risk unknown" path already handles if age is in
      // scope but obs are incomplete. See ClinicalWorkflows.md §7.
      isPregnant: false,
      observations: vitals?.news2Input,
      vitalsRecordedAt: vitals?.recordedAt,
      vitalsRecordId: vitals?.id,
      flags: _flagsOf(patient, r.appointment),
    );
  }

  /// Red flags from the presenting complaint. A waiting patient may have no
  /// note yet, but their reason for coming is already on the appointment —
  /// "chest pain" there should pull them into the attention tier before any
  /// vitals are taken. Uses the shared red-flag dictionary, negation and all.
  static List<ClinicalFlag> _flagsOf(Patient patient, Appointment appointment) {
    final text = <String?>[appointment.reason, appointment.notes]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join('. ');
    return RedFlagRule.fromText(patient.id, text, source: 'Presenting complaint');
  }
}
