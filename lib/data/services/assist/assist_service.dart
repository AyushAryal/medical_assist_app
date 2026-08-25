import '../../../clinical/insights/duplicate_detector.dart';
import '../../../clinical/insights/note_intelligence.dart';
import '../../../clinical/insights/schedule_insights.dart';
import '../../../clinical/insights/trend_analysis.dart';
import '../../models/appointment.dart';
import '../../models/patient.dart';
import '../../models/vitals_record.dart';

/// One entry point for everything the app works out on its own.
///
/// All of it is deterministic: dictionary matching, string similarity, robust
/// line fitting, medians. No model, no training, no inference — which is what
/// makes it instant, free, identical on every device, and explainable to the
/// clinician who is being asked to act on it.
///
/// The optional on-device model deliberately does **not** live here: its
/// three tasks each have a dedicated owner — question rewriting in
/// `ai/interpreters/model_interpreter.dart`, note drafting in
/// `note_drafting.dart` — each with its own gate. A general-purpose handle on
/// a language model is exactly the affordance that grows ungated uses.
class AssistService {
  AssistService();

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Existing records that may be the person being registered.
  List<DuplicateCandidate> possibleDuplicates({
    required Patient candidate,
    required Iterable<Patient> register,
  }) {
    return DuplicateDetector.search(
      _identity(candidate),
      register.map(_identity),
    );
  }

  static PatientIdentity _identity(Patient patient) => PatientIdentity(
        id: patient.id,
        givenName: patient.givenName,
        familyName: patient.familyName,
        dateOfBirth: patient.dateOfBirth,
        dobIsEstimated: patient.dobIsEstimated,
        phone: patient.phone,
        altPhone: patient.altPhone,
        nationalId: patient.nationalId,
        mrn: patient.mrn,
        sexAtBirth: patient.sexAtBirth.name,
      );

  // ---------------------------------------------------------------------------
  // Observations
  // ---------------------------------------------------------------------------

  /// Every vital-sign series that is moving the wrong way, worst first.
  ///
  /// Returns only deterioration. A list that also contained "improving" and
  /// "steady" would be a report, and a clinician mid-clinic does not read
  /// reports — they read warnings, and only while warnings stay rare.
  List<TrendResult> deterioratingTrends(List<VitalsRecord> history) {
    if (history.length < TrendAnalysis.minimumPoints) return const <TrendResult>[];

    final results = <TrendResult>[
      _trend('Systolic BP', history, TrendSensitivity.systolic,
          (v) => v.systolicBp?.toDouble()),
      _trend('Pulse', history, TrendSensitivity.heartRate,
          (v) => v.heartRate?.toDouble()),
      _trend('Respiratory rate', history, TrendSensitivity.respiratoryRate,
          (v) => v.respiratoryRate?.toDouble()),
      _trend('SpO₂', history, TrendSensitivity.spo2, (v) => v.spo2?.toDouble()),
      _trend('Weight', history, TrendSensitivity.weight, (v) => v.weightKg),
      _trend('Temperature', history, TrendSensitivity.temperature,
          (v) => v.temperatureC),
      _trend('Blood glucose', history, TrendSensitivity.glucose,
          (v) => v.bloodGlucoseMmol),
    ].where((t) => t.isNotable).toList();

    // Steepest relative move first — the one most worth a second look.
    results.sort(
      (a, b) => (b.changeOverSpan.abs() / (b.first.abs() + 1))
          .compareTo(a.changeOverSpan.abs() / (a.first.abs() + 1)),
    );
    return results;
  }

  TrendResult _trend(
    String label,
    List<VitalsRecord> history,
    TrendSensitivity sensitivity,
    double? Function(VitalsRecord) select,
  ) {
    return TrendAnalysis.analyse(
      label: label,
      points: <TrendPoint>[
        for (final record in history)
          if (select(record) case final value?)
            TrendPoint(at: record.recordedAt, value: value),
      ],
      sensitivity: sensitivity,
    );
  }

  /// The unit a trend's values are in, for its explanation sheet.
  static String unitFor(String label) => switch (label) {
        'Systolic BP' => 'mmHg',
        'Pulse' => 'bpm',
        'Respiratory rate' => '/min',
        'SpO₂' => '%',
        'Weight' => 'kg',
        'Temperature' => '°C',
        'Blood glucose' => 'mmol/L',
        _ => '',
      };

  // ---------------------------------------------------------------------------
  // Notes
  // ---------------------------------------------------------------------------

  /// Structured entries suggested by what has been written or dictated.
  List<ExtractedTerm> suggestionsFrom(String noteText) =>
      NoteIntelligence.extract(noteText);

  FollowUpMention? followUpFrom(String noteText) =>
      NoteIntelligence.followUp(noteText);

  // ---------------------------------------------------------------------------
  // Schedule
  // ---------------------------------------------------------------------------

  NoShowRisk attendanceRisk({
    required List<Appointment> history,
    required Appointment upcoming,
  }) {
    return NoShowEstimator.estimate(
      history: history.map(_outcome).toList(),
      scheduledFor: upcoming.scheduledAt,
      bookedAt: upcoming.createdAt,
    );
  }

  WaitEstimate waitEstimate({
    required int aheadInQueue,
    required List<Appointment> completedToday,
    String? visitType,
  }) {
    return WaitTimeEstimator.estimate(
      aheadInQueue: aheadInQueue,
      completedVisits: completedToday.map(_outcome).toList(),
      visitType: visitType,
    );
  }

  static AppointmentOutcome _outcome(Appointment appointment) {
    final started = appointment.startedAt;
    final completed = appointment.completedAt;
    return AppointmentOutcome(
      scheduledAt: appointment.scheduledAt,
      bookedAt: appointment.createdAt,
      attended: appointment.status == AppointmentStatus.completed ||
          appointment.status == AppointmentStatus.inProgress ||
          appointment.arrivedAt != null,
      wasCancelled: appointment.status == AppointmentStatus.cancelled,
      consultationMinutes: started == null || completed == null
          ? null
          : completed.difference(started).inMinutes,
      visitType: appointment.type.name,
    );
  }
}
