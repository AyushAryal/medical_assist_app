import 'package:flutter/foundation.dart';

import '../../clinical/insights/trend_analysis.dart';
import '../../clinical/patient_age.dart';
import '../../clinical/summary/handoff.dart';
import '../../clinical/summary/record_summary.dart';
import '../../data/models/allergy.dart';
import '../../data/models/clinical_note.dart';
import '../../data/models/attachment.dart';
import '../../data/models/encounter.dart';
import '../../data/models/medication.dart';
import '../../data/models/patient.dart';
import '../../data/models/problem.dart';
import '../../data/models/vitals_record.dart';
import '../../data/repositories/clinical_repository.dart';
import '../../data/services/assist/assist_service.dart';
import '../../data/summary/chart_summary.dart';

/// Loads everything the chart shows in one pass.
///
/// A chart is read as a whole — a clinician scanning a patient before a
/// consultation wants allergies, problems, medications and the last
/// observations on screen together, not revealed one lazy section at a time.
/// One visit, with everything recorded during it resolved alongside it.
///
/// The history list used to show an encounter's chief complaint and nothing
/// else, which meant reading last month's visit was a tap into a separate
/// screen and a tap back. A clinician skimming a history is looking for *what
/// was found and what was done*, and both live in the note — so the note, the
/// observations taken during the visit and its attachments are loaded with it.
typedef VisitRecord = ({
  Encounter encounter,
  ClinicalNote? note,
  List<VitalsRecord> vitals,
  List<Attachment> attachments,
});

class PatientChartController extends ChangeNotifier {
  PatientChartController(
    this._repository,
    this.patientId, {
    AssistService? assist,
  }) : _assist = assist ?? AssistService();

  final ClinicalRepository _repository;
  final AssistService _assist;
  final String patientId;

  bool _isLoading = true;
  Patient? _patient;
  List<Allergy> _allergies = const <Allergy>[];
  List<Problem> _problems = const <Problem>[];
  List<Medication> _medications = const <Medication>[];
  List<Encounter> _encounters = const <Encounter>[];
  List<VitalsRecord> _vitals = const <VitalsRecord>[];
  List<Attachment> _attachments = const <Attachment>[];
  List<VisitRecord> _visits = const <VisitRecord>[];
  List<TrendResult> _concerningTrends = const <TrendResult>[];

  bool get isLoading => _isLoading;
  Patient? get patient => _patient;
  List<Allergy> get allergies => _allergies;
  List<Problem> get problems => _problems;
  List<Medication> get medications => _medications;
  List<Encounter> get encounters => _encounters;
  List<VitalsRecord> get vitals => _vitals;
  List<Attachment> get attachments => _attachments;

  /// Visits newest first, each with its note, observations and files.
  List<VisitRecord> get visits => _visits;

  /// Observations moving the wrong way. Empty is the normal case, and the UI
  /// shows nothing at all when it is — a panel that usually says "no concerns"
  /// is one people stop reading.
  List<TrendResult> get concerningTrends => _concerningTrends;

  PatientAge? get age => _patient?.age;

  VitalsRecord? get latestVitals => _vitals.isEmpty ? null : _vitals.first;

  /// The set before [latestVitals], used to show deltas. Trend is what turns
  /// a number into information.
  VitalsRecord? get previousVitals => _vitals.length < 2 ? null : _vitals[1];

  List<Problem> get activeProblems =>
      _problems.where((p) => p.isActive).toList(growable: false);

  List<Medication> get activeMedications =>
      _medications.where((m) => m.isActive).toList(growable: false);

  /// A deterministic, sourced prime-the-chart pre-read of the loaded record —
  /// honest about what is not recorded. Null until the patient has loaded.
  /// Computed from data already on screen, so it costs no extra query.
  RecordSummary? get recordSummary {
    final p = _patient;
    if (p == null) return null;
    return ChartSummary.build(
      patient: p,
      allergies: _allergies,
      activeProblems: activeProblems,
      activeMedications: activeMedications,
      latestVitals: latestVitals,
      asOf: DateTime.now(),
    );
  }

  /// A deterministic SBAR handoff for passing this patient to another
  /// clinician. Reuses the pre-read for Background, adds the current concerns
  /// (deteriorating trends) and outstanding tasks. Null until loaded.
  Handoff? get handoff {
    final p = _patient;
    final summary = recordSummary;
    if (p == null || summary == null) return null;

    final concerns = <String>[
      for (final t in _concerningTrends)
        '${t.label}: ${t.direction.label.toLowerCase()}',
    ];

    final outstanding = <String>[];
    final open = openEncounter;
    if (open != null) {
      final note = _visits
          .where((v) => v.encounter.id == open.id)
          .map((v) => v.note)
          .firstOrNull;
      if (note == null || note.status == NoteStatus.draft) {
        outstanding.add('Complete and sign the note for the open visit');
      }
    }

    return HandoffBuilder.build(HandoffInput(
      patientId: p.id,
      asOf: DateTime.now(),
      identityLine: '${p.displayName} · ${p.identityLine}',
      record: summary,
      presentingComplaint: open?.chiefComplaint,
      concerns: concerns,
      outstanding: outstanding,
    ));
  }

  Encounter? get openEncounter =>
      _encounters.where((e) => e.isOpen).firstOrNull;

  /// Loads the chart and writes the access audit entry exactly once.
  Future<void> load({bool recordAccess = true}) async {
    _isLoading = true;
    notifyListeners();

    _patient = recordAccess
        ? await _repository.openPatient(patientId)
        : await _repository.patients.byId(patientId);

    if (_patient != null) {
      _allergies = await _repository.patients.allergies(
        patientId,
        activeOnly: false,
      );
      _problems = await _repository.patients.problems(patientId);
      _medications = await _repository.patients.medications(patientId);
      _encounters = await _repository.encounters.forPatient(patientId);
      _vitals = await _repository.vitals.forPatient(patientId, limit: 30);
      _attachments = await _repository.attachments.forPatient(patientId);
      _visits = await _resolveVisits(_encounters);
      // Oldest first for the fit; the DAO returns newest first.
      _concerningTrends = _assist.deterioratingTrends(
        _vitals.reversed.toList(growable: false),
      );
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() => load(recordAccess: false);

  /// Assembles the visit history in one pass.
  ///
  /// Bounded rather than unlimited: a patient with fifteen years of monthly
  /// visits would otherwise cost hundreds of queries to open a chart. Older
  /// visits stay reachable through the encounter screen.
  Future<List<VisitRecord>> _resolveVisits(List<Encounter> encounters) async {
    final visits = <VisitRecord>[];
    for (final encounter in encounters.take(visitHistoryLimit)) {
      visits.add((
        encounter: encounter,
        note: await _repository.notes.forEncounter(encounter.id),
        vitals: await _repository.vitals.forEncounter(encounter.id),
        attachments: _attachments
            .where((a) => a.ownerId == encounter.id)
            .toList(growable: false),
      ));
    }
    return visits;
  }

  static const int visitHistoryLimit = 25;

  /// True when there are older visits than the history shows.
  bool get hasOlderVisits => _encounters.length > visitHistoryLimit;

  /// Files not tied to a single visit, plus everything else, newest first.
  List<Attachment> get documents {
    final sorted = _attachments.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  Future<void> addAllergy(Allergy allergy) async {
    await _repository.patients.addAllergy(allergy);
    await refresh();
  }

  Future<void> addProblem(Problem problem) async {
    await _repository.patients.addProblem(problem);
    await refresh();
  }

  Future<void> addMedication(Medication medication) async {
    await _repository.patients.addMedication(medication);
    await refresh();
  }

  /// Formats the change in a numeric observation since the previous set.
  String? deltaFor(num? current, num? previous, {int decimals = 0}) {
    if (current == null || previous == null) return null;
    final difference = current - previous;
    if (difference == 0) return 'no change';
    final sign = difference > 0 ? '+' : '−';
    return '$sign${difference.abs().toStringAsFixed(decimals)}';
  }
}
