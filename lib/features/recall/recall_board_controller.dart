import 'package:flutter/foundation.dart';

import '../../clinical/worklist/recall_worklist.dart';
import '../../clinical/worklist/worklist.dart';
import '../../data/repositories/clinical_repository.dart';
import '../../data/worklist/recall_board_service.dart';

/// Drives the recall list: loads the ranked overdue reviews. All ranking lives
/// in the pure engine; this only fetches.
class RecallBoardController extends ChangeNotifier {
  RecallBoardController(ClinicalRepository repository)
      : _service = RecallBoardService(
          encounters: repository.encounters,
          patients: repository.patients,
        );

  final RecallBoardService _service;

  bool _isLoading = true;
  Worklist? _worklist;
  Map<String, RecallSubject> _subjects = const <String, RecallSubject>{};

  bool get isLoading => _isLoading;
  int get dueCount => _worklist?.entries.length ?? 0;
  List<WorklistEntry> get entries => _worklist?.entries ?? const <WorklistEntry>[];

  RecallSubject? subjectFor(String patientId) => _subjects[patientId];

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    final board = await _service.load();
    _worklist = board.ranked;
    _subjects = <String, RecallSubject>{
      for (final s in board.model.subjects) s.patientId: s,
    };

    _isLoading = false;
    notifyListeners();
  }
}
