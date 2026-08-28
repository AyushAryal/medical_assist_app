import '../../data/models/allergy.dart';
import '../../data/repositories/clinical_repository.dart';
import '../utils/formatters.dart';

/// Reads a patient's record and formats the pieces a note actually reaches for.
///
/// This is what makes a smart phrase *smart*: `\vitals` does not paste a
/// template, it pastes the numbers last written for this patient. Every method
/// returns text ready to drop into a field, and a plain honest sentence when
/// there is nothing on file — a blank is worse than "No vitals recorded".
abstract final class PatientPhraseData {
  static Future<String> vitals(
    ClinicalRepository repository,
    String patientId,
  ) async {
    final v = await repository.vitals.latestForPatient(patientId);
    if (v == null) return 'No vital signs on file.';
    final parts = <String>[
      if (v.systolicBp != null && v.diastolicBp != null)
        'BP ${v.systolicBp}/${v.diastolicBp}',
      if (v.heartRate != null) 'HR ${v.heartRate}',
      if (v.respiratoryRate != null) 'RR ${v.respiratoryRate}',
      if (v.temperatureC != null) 'Temp ${v.temperatureC}°C',
      if (v.spo2 != null) 'SpO₂ ${v.spo2}%',
      if (v.weightKg != null) 'Wt ${v.weightKg}kg',
    ];
    if (parts.isEmpty) return 'No vital signs on file.';
    return '${parts.join(', ')} (recorded ${Fmt.dateTime(v.recordedAt)})';
  }

  static Future<String> allergies(
    ClinicalRepository repository,
    String patientId,
  ) async {
    final allergies =
        await repository.patients.allergies(patientId, activeOnly: true);
    if (allergies.isEmpty) return 'No known allergies.';
    return 'Allergies: ${allergies.map((a) {
      final dangerous = a.severity == AllergySeverity.severe ||
          a.severity == AllergySeverity.anaphylaxis;
      final reaction = a.reaction?.trim();
      final detail = <String>[
        if (dangerous) a.severity.label,
        if (reaction != null && reaction.isNotEmpty) reaction,
      ].join(', ');
      return detail.isEmpty ? a.substance : '${a.substance} ($detail)';
    }).join('; ')}';
  }

  static Future<String> medications(
    ClinicalRepository repository,
    String patientId,
  ) async {
    final meds = await repository.patients.medications(patientId);
    final active = meds.where((m) => m.isActive).toList();
    if (active.isEmpty) return 'No current medications.';
    return active.map((m) {
      final parts = <String>[
        m.name,
        if (m.dose != null) m.dose!,
        if (m.route != null) m.route!,
        if (m.frequency != null) m.frequency!,
      ];
      return parts.join(' ');
    }).join('; ');
  }

  static Future<String> problems(
    ClinicalRepository repository,
    String patientId,
  ) async {
    final problems = await repository.patients.problems(patientId);
    final active = problems.where((p) => p.isActive).toList();
    if (active.isEmpty) return 'No active problems recorded.';
    return active
        .map((p) => p.isChronic ? '${p.display} (chronic)' : p.display)
        .join('; ');
  }

  /// The history of the presenting illness from the most recent note — the
  /// subjective the last clinician wrote, so a returning patient's story carries
  /// forward instead of being re-taken from scratch.
  static Future<String> historyOfPresentIllness(
    ClinicalRepository repository,
    String patientId,
  ) async {
    final notes = await repository.notes.forPatient(patientId, limit: 1);
    final subjective = notes.isEmpty ? null : notes.first.subjective?.trim();
    if (subjective == null || subjective.isEmpty) {
      return 'No prior history recorded.';
    }
    return subjective;
  }
}
