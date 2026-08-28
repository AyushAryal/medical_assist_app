import '../../clinical/insights/trend_analysis.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/allergy.dart';
import '../../data/models/encounter.dart';
import '../../data/models/patient.dart';
import '../../data/repositories/clinical_repository.dart';
import '../../data/services/assist/assist_service.dart';
import '../intent.dart';
import '../presentation.dart';
import '../provenance.dart';

/// Assembles a patient summary from the record — never generated.
///
/// Everything here is a read of the chart, formatted for reading: the same data
/// the chart screen shows, gathered into one answer because the question was
/// "tell me about this person" rather than "open their file". Holding to
/// deterministic assembly is what keeps a patient summary inside this app's
/// contract: a model may have *reshaped the request* into "summarise «id»", but
/// it contributes not one word of the summary itself.
class PatientSummaryHandler {
  PatientSummaryHandler(this._repository) : _assist = AssistService();

  final ClinicalRepository _repository;
  final AssistService _assist;

  Future<Presentation> run(
    PatientSummaryIntent intent,
    Provenance provenance,
  ) async {
    final patient = await _repository.openPatient(intent.patientId);
    if (patient == null) {
      return const MessagePresentation(
        headline: 'That patient is no longer on the register.',
      );
    }

    final allergies =
        await _repository.patients.allergies(patient.id, activeOnly: true);
    final problems = await _repository.patients.problems(patient.id);
    final medications = await _repository.patients.medications(patient.id);
    final vitals = await _repository.vitals.forPatient(patient.id, limit: 30);
    final encounters =
        await _repository.encounters.forPatient(patient.id, limit: 5);
    final appointments =
        await _repository.appointments.forPatient(patient.id, limit: 20);

    // Trends read oldest→newest.
    final trends = _assist.deterioratingTrends(vitals.reversed.toList());

    final latest = vitals.isEmpty ? null : vitals.first;
    final now = DateTime.now();

    final visits = <({String when, String summary})>[];
    for (final encounter in encounters.take(3)) {
      final note = await _repository.notes.forEncounter(encounter.id);
      final assessment = note?.assessment?.trim();
      final complaint = encounter.chiefComplaint?.trim();
      final parts = <String>[
        encounter.type.label,
        if (complaint != null && complaint.isNotEmpty) complaint,
        if (assessment != null && assessment.isNotEmpty) '— $assessment',
      ];
      visits.add((when: Fmt.date(encounter.startedAt), summary: parts.join(' ')));
    }

    final upcoming = <String>[
      for (final appt in appointments)
        if (appt.scheduledAt.isAfter(now))
          '${Fmt.dateTime(appt.scheduledAt)} — ${appt.reason ?? appt.type.label}',
    ]..sort();

    provenance.add(
      'execute',
      'Gathered ${patient.displayName} from the record',
      detail: 'Deterministic — every line is read from the chart, none generated.',
    );

    return PatientSummaryPresentation(
      headline: intent.mode == PatientSummaryMode.progression
          ? 'How ${patient.displayName} is progressing'
          : '${patient.displayName} — summary',
      patientId: patient.id,
      identityLine: patient.identityLine,
      progression: intent.mode == PatientSummaryMode.progression,
      allergyLine: _allergyLine(patient.allergyStatus, allergies),
      problems: <String>[
        for (final problem in problems)
          if (problem.isActive)
            problem.isChronic ? '${problem.display} (chronic)' : problem.display,
      ],
      medications: <String>[
        for (final med in medications)
          if (med.isActive) _medicationLine(med),
      ],
      vitals: latest == null ? const [] : _vitalsLines(latest),
      news2Line: _news2Line(latest, now),
      trends: <String>[
        for (final trend in trends)
          '${trend.label} ${trend.direction.label} — '
              '${trend.first.toStringAsFixed(0)} to '
              '${trend.last.toStringAsFixed(0)} '
              '${AssistService.unitFor(trend.label)} over '
              '${trend.points} readings',
      ],
      visits: visits,
      upcoming: upcoming.take(3).toList(),
    );
  }

  String? _allergyLine(AllergyStatus status, List<Allergy> allergies) {
    if (allergies.isEmpty) {
      return status == AllergyStatus.noKnownAllergies
          ? 'No known allergies'
          : null;
    }
    return 'Allergies: ${allergies.map((a) {
      final dangerous = a.severity == AllergySeverity.severe ||
          a.severity == AllergySeverity.anaphylaxis;
      return dangerous ? '${a.substance} (${a.severity.label})' : a.substance;
    }).join(', ')}';
  }

  String _medicationLine(dynamic med) {
    final parts = <String>[
      med.name as String,
      if (med.dose != null) med.dose as String,
      if (med.route != null) med.route as String,
      if (med.frequency != null) med.frequency as String,
    ];
    return parts.join(' · ');
  }

  List<({String label, String value})> _vitalsLines(dynamic v) {
    final out = <({String label, String value})>[];
    if (v.systolicBp != null && v.diastolicBp != null) {
      out.add((label: 'BP', value: '${v.systolicBp}/${v.diastolicBp} mmHg'));
    }
    if (v.heartRate != null) out.add((label: 'HR', value: '${v.heartRate} bpm'));
    if (v.respiratoryRate != null) {
      out.add((label: 'RR', value: '${v.respiratoryRate} /min'));
    }
    if (v.temperatureC != null) {
      out.add((label: 'Temp', value: '${v.temperatureC} °C'));
    }
    if (v.spo2 != null) out.add((label: 'SpO₂', value: '${v.spo2}%'));
    if (v.weightKg != null) {
      out.add((label: 'Weight', value: '${v.weightKg} kg'));
    }
    return out;
  }

  String? _news2Line(dynamic latest, DateTime now) {
    if (latest == null || latest.news2Score == null) return null;
    final score = latest.news2Score as int;
    final band = score >= 7
        ? 'high risk'
        : score >= 5
            ? 'medium risk'
            : score >= 1
                ? 'low–medium risk'
                : 'low risk';
    return 'NEWS2 $score — $band, recorded ${Fmt.dateTime(latest.recordedAt)}';
  }
}
