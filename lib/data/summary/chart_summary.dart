import '../../clinical/news2.dart';
import '../../clinical/patient_age.dart';
import '../../clinical/summary/record_summary.dart';
import '../../clinical/summary/summary_builder.dart';
import '../models/allergy.dart';
import '../models/medication.dart';
import '../models/patient.dart';
import '../models/problem.dart';
import '../models/vitals_record.dart';

/// Maps a loaded patient chart into the clinical [ChartSnapshot], then into a
/// [RecordSummary].
///
/// Pure: it takes model objects the chart already loaded — no DAOs, no extra
/// queries — so the prime-the-chart summary is a projection of what is on
/// screen, computed once and testable with fixtures. The allergy *state* comes
/// from the patient's three-way status (the honest source of "asked, none" vs
/// "not asked"), while the substances come from the active allergy rows.
abstract final class ChartSummary {
  static RecordSummary build({
    required Patient patient,
    required List<Allergy> allergies,
    required List<Problem> activeProblems,
    required List<Medication> activeMedications,
    required VitalsRecord? latestVitals,
    required DateTime asOf,
  }) =>
      SummaryBuilder.build(snapshot(
        patient: patient,
        allergies: allergies,
        activeProblems: activeProblems,
        activeMedications: activeMedications,
        latestVitals: latestVitals,
        asOf: asOf,
      ));

  static ChartSnapshot snapshot({
    required Patient patient,
    required List<Allergy> allergies,
    required List<Problem> activeProblems,
    required List<Medication> activeMedications,
    required VitalsRecord? latestVitals,
    required DateTime asOf,
  }) {
    final active = allergies
        .where((a) => a.status == AllergyRecordStatus.active)
        .toList(growable: false);

    return ChartSnapshot(
      patientId: patient.id,
      asOf: asOf,
      allergyState: _allergyState(patient.allergyStatus),
      allergies: <AllergyLine>[
        for (final a in active)
          (
            substance: a.substance,
            severityLabel: a.severity == AllergySeverity.unknown
                ? null
                : a.severity.label,
            isHigh: a.severity == AllergySeverity.severe ||
                a.severity == AllergySeverity.anaphylaxis,
          ),
      ],
      activeProblems: <String>[for (final p in activeProblems) p.display],
      currentMedications: <String>[
        for (final m in activeMedications) _medicationLine(m),
      ],
      latestObs: _obsOf(latestVitals, patient),
      lastEncounterAt: patient.lastSeenAt,
    );
  }

  static AllergyRecordState _allergyState(AllergyStatus status) =>
      switch (status) {
        AllergyStatus.unknown => AllergyRecordState.notRecorded,
        AllergyStatus.noKnownAllergies => AllergyRecordState.noneKnown,
        AllergyStatus.hasAllergies => AllergyRecordState.present,
      };

  static String _medicationLine(Medication m) => <String?>[
        m.name,
        m.dose,
        m.doseUnit,
      ].where((s) => s != null && s.isNotEmpty).join(' ');

  /// Runs the same [News2Calculator] the rest of the app uses, so the score on
  /// the pre-read matches the score everywhere else. Pregnancy is not modelled,
  /// so NEWS2 refuses only on age — see ClinicalWorkflows.md §8.
  static ObsView? _obsOf(VitalsRecord? vitals, Patient patient) {
    if (vitals == null) return null;
    final age = PatientAge.fromDateOfBirth(patient.dateOfBirth);
    final input = vitals.news2Input;
    final reason = News2Calculator.unavailableReason(
      ageYears: age?.years,
      isPregnant: false,
      input: input,
    );
    final result = reason == null
        ? News2Calculator.score(
            ageYears: age?.years,
            isPregnant: false,
            input: input,
          )
        : null;
    return ObsView(
      recordedAt: vitals.recordedAt,
      risk: result?.risk,
      news2Total: result?.total,
      unavailableReason: result == null ? reason : null,
    );
  }
}
