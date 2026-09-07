import '../../clinical/worklist/recall_worklist.dart';
import '../models/encounter.dart';
import '../models/patient.dart';

/// A candidate patient with their encounter history, for the recall rule.
typedef RecallRecord = ({Patient patient, List<Encounter> encounters});

/// Maps encounter history into the recall read model.
///
/// Pure. The rule of "due": a patient's **most recent** encounter carries a
/// follow-up date that has passed. Keying off the most recent visit is what
/// makes "seen since" fall out for free — if the patient came back, that later
/// visit is the most recent one, and its follow-up (or absence of one) governs.
/// A review that was met, or superseded by a newer plan, therefore drops off
/// the list without any special case.
abstract final class RecallAssembly {
  static RecallReadModel build({
    required DateTime asOf,
    required Iterable<RecallRecord> records,
  }) {
    final subjects = <RecallSubject>[];
    for (final r in records) {
      if (r.encounters.isEmpty) continue;
      final latest = r.encounters
          .reduce((a, b) => a.startedAt.isAfter(b.startedAt) ? a : b);

      final due = latest.followUpDate;
      if (due == null || due.isAfter(asOf)) continue; // none, or not yet due

      subjects.add(RecallSubject(
        patientId: r.patient.id,
        mrn: r.patient.mrn,
        displayName: r.patient.displayName,
        dueDate: due,
        lastSeenAt: latest.startedAt,
        reason: latest.chiefComplaint,
      ));
    }
    return RecallReadModel(asOf: asOf, subjects: subjects);
  }
}
