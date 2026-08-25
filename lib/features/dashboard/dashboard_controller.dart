import 'package:flutter/foundation.dart';

import '../../data/models/appointment.dart';
import '../../data/models/clinical_note.dart';
import '../../data/models/encounter.dart';
import '../../data/models/patient.dart';
import '../../data/models/vitals_record.dart';
import '../../data/repositories/clinical_repository.dart';

/// A row in the "needs attention" list: an observation set plus the patient it
/// belongs to, resolved once so the list does not query per row.
typedef FlaggedObservation = ({VitalsRecord vitals, Patient patient});

/// A piece of outstanding work: an encounter, its patient, and whether the
/// note has been written.
/// A booked slot resolved with its patient, for the dashboard schedule strip.
typedef ScheduleItem = ({Appointment appointment, Patient patient});

typedef OpenWorkItem = ({
  Encounter encounter,
  Patient patient,
  ClinicalNote? note,
});

/// Assembles the dashboard.
///
/// The ordering of what it loads reflects what a clinician actually needs:
/// unfinished charting first (it is the thing with a deadline), then patients
/// whose observations are off, then the day's activity, then quick re-entry
/// into recent charts.
class DashboardController extends ChangeNotifier {
  DashboardController(this._repository);

  final ClinicalRepository _repository;

  bool _isLoading = true;
  int _draftNoteCount = 0;
  int _todayEncounterCount = 0;
  int _todayVitalsCount = 0;
  int _pendingSyncCount = 0;
  int _patientCount = 0;
  List<OpenWorkItem> _openWork = const <OpenWorkItem>[];
  List<FlaggedObservation> _flagged = const <FlaggedObservation>[];
  List<Encounter> _followUpsDue = const <Encounter>[];
  List<Patient> _recentPatients = const <Patient>[];
  List<ScheduleItem> _todaySchedule = const <ScheduleItem>[];
  int _waitingCount = 0;
  int _remainingToday = 0;
  List<({String label, int value})> _weekActivity = const [];

  bool get isLoading => _isLoading;
  int get draftNoteCount => _draftNoteCount;
  int get todayEncounterCount => _todayEncounterCount;
  int get todayVitalsCount => _todayVitalsCount;
  int get pendingSyncCount => _pendingSyncCount;
  int get patientCount => _patientCount;
  List<OpenWorkItem> get openWork => _openWork;
  List<FlaggedObservation> get flagged => _flagged;
  List<Encounter> get followUpsDue => _followUpsDue;
  List<Patient> get recentPatients => _recentPatients;
  List<ScheduleItem> get todaySchedule => _todaySchedule;

  /// Patients checked in and still waiting to be called.
  int get waitingCount => _waitingCount;

  /// Booked slots today that have not yet reached a terminal status.
  int get remainingToday => _remainingToday;

  /// The next slot still to be seen, or null once the list is clear.
  /// Encounters per day over the last seven days, oldest first. Enough to see
  /// whether the week is busier than usual; not enough to pretend it is
  /// analytics.
  List<({String label, int value})> get weekActivity => _weekActivity;

  ScheduleItem? get nextUp => _todaySchedule
      .where((item) => !item.appointment.status.isFinished)
      .firstOrNull;

  bool get hasOutstandingWork => _openWork.isNotEmpty || _draftNoteCount > 0;

  Future<void> load({String? clinicId}) async {
    _isLoading = true;
    notifyListeners();

    final today = DateTime.now();

    final todayEncounters = await _repository.encounters.forDay(
      today,
      clinicId: clinicId,
    );
    final open = await _repository.encounters.openOrUnsigned(limit: 25);
    final flaggedVitals = await _repository.vitals.elevatedToday(today);

    _draftNoteCount = await _repository.notes.draftCount();
    _todayEncounterCount = todayEncounters.length;
    _todayVitalsCount = await _repository.vitals.countForDay(today);
    _pendingSyncCount = await _repository.pendingSyncCount();
    _patientCount = await _repository.patients.count();
    _followUpsDue = await _repository.encounters.followUpsDue(today);
    _recentPatients = await _repository.patients.recent(limit: 8);

    final appointments = await _repository.appointments.forDay(
      today,
      clinicId: clinicId,
    );
    _todaySchedule = await _resolveSchedule(appointments);
    _waitingCount =
        _todaySchedule.where((i) => i.appointment.status.isWaiting).length;
    _remainingToday =
        _todaySchedule.where((i) => !i.appointment.status.isFinished).length;

    _weekActivity = await _loadWeekActivity(today);
    _openWork = await _resolveOpenWork(open);
    _flagged = await _resolveFlagged(flaggedVitals);

    _isLoading = false;
    notifyListeners();
  }

  static const List<String> _weekdayInitials = <String>[
    'M', 'T', 'W', 'T', 'F', 'S', 'S',
  ];

  Future<List<({String label, int value})>> _loadWeekActivity(
    DateTime today,
  ) async {
    final result = <({String label, int value})>[];
    for (var offset = 6; offset >= 0; offset--) {
      final day = today.subtract(Duration(days: offset));
      final encounters = await _repository.encounters.forDay(day);
      result.add((
        // DateTime.weekday is 1=Monday.
        label: _weekdayInitials[day.weekday - 1],
        value: encounters.length,
      ));
    }
    return result;
  }

  Future<List<ScheduleItem>> _resolveSchedule(
    List<Appointment> appointments,
  ) async {
    final items = <ScheduleItem>[];
    for (final appointment in appointments) {
      final patient = await _repository.patients.byId(appointment.patientId);
      if (patient == null) continue;
      items.add((appointment: appointment, patient: patient));
    }
    return items;
  }

  Future<List<OpenWorkItem>> _resolveOpenWork(List<Encounter> encounters) async {
    final items = <OpenWorkItem>[];
    for (final encounter in encounters) {
      // Read the patient directly rather than through `openPatient`: building
      // the dashboard is not a chart access and must not fill the audit log.
      final patient = await _repository.patients.byId(encounter.patientId);
      if (patient == null) continue;
      final note = await _repository.notes.forEncounter(encounter.id);
      items.add((encounter: encounter, patient: patient, note: note));
    }
    return items;
  }

  Future<List<FlaggedObservation>> _resolveFlagged(
    List<VitalsRecord> records,
  ) async {
    final seen = <String>{};
    final items = <FlaggedObservation>[];
    for (final record in records) {
      // One row per patient — the highest-scoring set, which the DAO returns
      // first. A list of six readings for the same person is noise.
      if (!seen.add(record.patientId)) continue;
      final patient = await _repository.patients.byId(record.patientId);
      if (patient == null) continue;
      items.add((vitals: record, patient: patient));
    }
    return items;
  }
}
