import 'package:flutter/foundation.dart';

import '../../clinical/worklist/triage_worklist.dart';
import '../../clinical/worklist/worklist.dart';
import '../../data/repositories/clinical_repository.dart';
import '../../data/worklist/triage_board_service.dart';

/// Drives the triage board: loads the ranked waiting room and splits it into
/// the two sections the screen renders. All ranking lives in the pure engine;
/// this only fetches and groups.
class TriageBoardController extends ChangeNotifier {
  TriageBoardController(ClinicalRepository repository)
      : _service = TriageBoardService(
          appointments: repository.appointments,
          patients: repository.patients,
          vitals: repository.vitals,
        );

  final TriageBoardService _service;

  bool _isLoading = true;
  Worklist? _worklist;
  Map<String, TriageSubject> _subjects = const <String, TriageSubject>{};

  bool get isLoading => _isLoading;
  DateTime? get asOf => _worklist?.asOf;
  int get waitingCount => _worklist?.entries.length ?? 0;

  /// Scored patients, and anyone carrying a critical flag — the list the
  /// clinician works down.
  List<WorklistEntry> get attention => _entriesIn(TriageGroup.attention);

  /// Risk unknown until observations exist — held apart so nobody reads an
  /// unmeasured patient as low priority.
  List<WorklistEntry> get needsObs => _entriesIn(TriageGroup.needsObs);

  TriageSubject? subjectFor(String patientId) => _subjects[patientId];

  Future<void> load({String? clinicId}) async {
    _isLoading = true;
    notifyListeners();

    final board = await _service.load(clinicId: clinicId);
    _worklist = board.ranked;
    _subjects = <String, TriageSubject>{
      for (final s in board.model.subjects) s.patientId: s,
    };

    _isLoading = false;
    notifyListeners();
  }

  List<WorklistEntry> _entriesIn(String group) =>
      _worklist?.entries.where((e) => e.group == group).toList() ??
      const <WorklistEntry>[];
}
