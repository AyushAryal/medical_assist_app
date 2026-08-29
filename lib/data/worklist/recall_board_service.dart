import '../../clinical/worklist/recall_worklist.dart';
import '../../clinical/worklist/worklist.dart';
import '../dao/encounter_dao.dart';
import '../dao/patient_dao.dart';
import 'recall_assembly.dart';

/// The recall list as the screen consumes it.
typedef RecallBoard = ({RecallReadModel model, Worklist ranked});

/// Finds patients overdue for review and ranks them.
///
/// A read-side composition of DAOs: the due-follow-up query narrows to
/// candidates, then each candidate's history is pulled so the pure
/// [RecallAssembly] can apply the most-recent-visit rule. All judgement lives
/// in the pure layers; this only fetches.
class RecallBoardService {
  RecallBoardService({required this.encounters, required this.patients});

  final EncounterDao encounters;
  final PatientDao patients;

  Future<RecallBoard> load({DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final dueEncounters = await encounters.followUpsDue(now);
    final patientIds = <String>{for (final e in dueEncounters) e.patientId};

    final records = <RecallRecord>[];
    for (final id in patientIds) {
      final patient = await patients.byId(id);
      if (patient == null) continue;
      records.add((patient: patient, encounters: await encounters.forPatient(id)));
    }

    final model = RecallAssembly.build(asOf: now, records: records);
    return (model: model, ranked: RecallWorklist.build(model));
  }
}
