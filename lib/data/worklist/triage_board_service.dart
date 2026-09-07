import '../../clinical/worklist/triage_worklist.dart';
import '../../clinical/worklist/worklist.dart';
import '../dao/appointment_dao.dart';
import '../dao/patient_dao.dart';
import '../dao/vitals_dao.dart';
import 'triage_assembly.dart';

/// The triage board as the screen consumes it: the ranked list plus the
/// snapshot it was ranked from, so a row can show the patient behind an id.
typedef TriageBoard = ({TriageReadModel model, Worklist ranked});

/// Reads the waiting room and ranks it for triage.
///
/// A read-side composition of DAOs — reads join across tables, so unlike a
/// mutation they do not go through the single write path. All the judgement
/// lives in the pure [TriageAssembly] and [TriageWorklist]; this only fetches
/// the rows and hands them over, which is why it needs no test of its own.
class TriageBoardService {
  TriageBoardService({
    required this.appointments,
    required this.patients,
    required this.vitals,
  });

  final AppointmentDao appointments;
  final PatientDao patients;
  final VitalsDao vitals;

  Future<TriageBoard> load({String? clinicId, DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final waiting = await appointments.waitingRoom(clinicId: clinicId);

    final records = <TriageRecord>[];
    for (final appt in waiting) {
      final patient = await patients.byId(appt.patientId);
      // A waiting appointment whose patient row is missing is a data fault, not
      // a triage decision; skip it here rather than inventing a subject. It is
      // rare, local, and self-healing on the next sync.
      if (patient == null) continue;
      final latest = await vitals.latestForPatient(appt.patientId);
      records.add((appointment: appt, patient: patient, latestVitals: latest));
    }

    final model = TriageAssembly.build(asOf: now, records: records);
    return (model: model, ranked: TriageWorklist.build(model));
  }
}
