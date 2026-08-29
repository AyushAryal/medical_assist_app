import 'worklist.dart';

/// The recall rule: patients whose review has fallen due and who have not been
/// seen since.
///
/// Pure and deterministic, like triage. "Due" is defined by a clinician's own
/// decision — the follow-up date they set on an encounter — never by a
/// hardcoded interval this file invented. The read model carries only patients
/// already past their review date with no later visit; the rule ranks them by
/// how overdue they are, so the person waiting longest for a review they were
/// promised surfaces first.

/// One patient due for review — the projection the rule needs.
class RecallSubject {
  const RecallSubject({
    required this.patientId,
    required this.mrn,
    required this.displayName,
    required this.dueDate,
    required this.lastSeenAt,
    this.reason,
  });

  final String patientId;
  final String mrn;
  final String displayName;

  /// The review date a clinician set. Already in the past for everyone here.
  final DateTime dueDate;

  /// When the visit that set the review happened.
  final DateTime lastSeenAt;

  /// What the review is for, when the encounter recorded it.
  final String? reason;
}

class RecallReadModel {
  const RecallReadModel({required this.asOf, required this.subjects});

  final DateTime asOf;
  final List<RecallSubject> subjects;
}

abstract final class RecallWorklist {
  static const String worklistId = 'recall';

  /// Ranks the overdue reviews, most overdue first. Every due patient is listed
  /// exactly once, so [Worklist.excluded] is empty by construction and
  /// `considered == entries.length`. (Whether a patient *is* due is decided
  /// upstream, in the assembler, from their follow-up date.)
  static Worklist build(RecallReadModel model) {
    final ordered = <RecallSubject>[...model.subjects]
      ..sort((a, b) => _compare(a, b));

    final entries = <WorklistEntry>[];
    for (var i = 0; i < ordered.length; i++) {
      final s = ordered[i];
      final overdueDays = model.asOf
          .difference(s.dueDate)
          .inDays
          .clamp(0, 1 << 31);
      entries.add(
        WorklistEntry(
          patientId: s.patientId,
          rank: i + 1,
          score: overdueDays,
          reasons: <String>[
            'Review due ${_date(s.dueDate)}',
            _overdueLabel(overdueDays),
            if (s.reason != null && s.reason!.trim().isNotEmpty)
              'For: ${s.reason!.trim()}',
          ],
          provenance: <ProvenanceRef>[
            ProvenanceRef(label: 'Review due', at: s.dueDate),
            ProvenanceRef(label: 'Last seen', at: s.lastSeenAt),
          ],
        ),
      );
    }

    return Worklist(
      id: worklistId,
      title: 'Recall',
      asOf: model.asOf,
      entries: entries,
      considered: model.subjects.length,
    );
  }

  /// Earliest due date first (most overdue), then MRN for a total order.
  static int _compare(RecallSubject a, RecallSubject b) {
    final byDue = a.dueDate.compareTo(b.dueDate);
    if (byDue != 0) return byDue;
    return a.mrn.compareTo(b.mrn);
  }

  static String _overdueLabel(int days) {
    if (days <= 0) return 'due today';
    if (days < 7) return '$days days overdue';
    if (days < 30) return '${days ~/ 7} wk overdue';
    return '${days ~/ 30} mo overdue';
  }

  static String _date(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)}';
  static String _two(int n) => n.toString().padLeft(2, '0');
}
