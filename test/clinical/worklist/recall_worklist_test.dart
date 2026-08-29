import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/worklist/recall_worklist.dart';
import 'package:medical_app/clinical/worklist/worklist.dart';

void main() {
  final asOf = DateTime(2026, 8, 29);

  RecallSubject due({
    required String id,
    required DateTime dueDate,
    String? mrn,
    String? reason,
  }) =>
      RecallSubject(
        patientId: id,
        mrn: mrn ?? id,
        displayName: id,
        dueDate: dueDate,
        lastSeenAt: dueDate.subtract(const Duration(days: 30)),
        reason: reason,
      );

  List<String> order(Worklist w) =>
      w.entries.map((e) => e.patientId).toList();

  test('ranks most overdue first', () {
    final w = RecallWorklist.build(RecallReadModel(asOf: asOf, subjects: [
      due(id: 'recent', dueDate: DateTime(2026, 8, 25)),
      due(id: 'oldest', dueDate: DateTime(2026, 6, 1)),
      due(id: 'mid', dueDate: DateTime(2026, 8, 1)),
    ]));
    expect(order(w), ['oldest', 'mid', 'recent']);
  });

  test('ties break by MRN for a total order', () {
    final d = DateTime(2026, 8, 10);
    final w = RecallWorklist.build(RecallReadModel(asOf: asOf, subjects: [
      due(id: 'c', dueDate: d, mrn: '003'),
      due(id: 'a', dueDate: d, mrn: '001'),
      due(id: 'b', dueDate: d, mrn: '002'),
    ]));
    expect(order(w), ['a', 'b', 'c']);
  });

  test('every subject is listed once, nothing excluded', () {
    final w = RecallWorklist.build(RecallReadModel(asOf: asOf, subjects: [
      due(id: 'a', dueDate: DateTime(2026, 8, 1)),
      due(id: 'b', dueDate: DateTime(2026, 8, 2)),
    ]));
    expect(w.considered, 2);
    expect(w.entries.length, 2);
    expect(w.excluded, isEmpty);
    expect(w.entries.map((e) => e.rank), [1, 2]);
  });

  test('reasons state the due date and how overdue, with provenance', () {
    final w = RecallWorklist.build(RecallReadModel(asOf: asOf, subjects: [
      due(id: 'a', dueDate: DateTime(2026, 8, 15), reason: 'BP review'),
    ]));
    final e = w.entries.single;
    expect(e.reasons, contains('Review due 2026-08-15'));
    expect(e.reasons.any((r) => r.contains('overdue')), isTrue);
    expect(e.reasons, contains('For: BP review'));
    expect(e.provenance.first.label, 'Review due');
    expect(e.score, 14); // 29 - 15 Aug
  });

  test('overdue phrasing scales with time', () {
    RecallSubject s(DateTime d) => due(id: 'p', dueDate: d);
    String label(DateTime d) => RecallWorklist.build(
          RecallReadModel(asOf: asOf, subjects: [s(d)]),
        ).entries.single.reasons[1];

    expect(label(DateTime(2026, 8, 29)), 'due today');
    expect(label(DateTime(2026, 8, 26)), '3 days overdue');
    expect(label(DateTime(2026, 8, 10)), '2 wk overdue');
    expect(label(DateTime(2026, 6, 1)), '2 mo overdue');
  });

  test('an empty recall list is empty, not an error', () {
    final w = RecallWorklist.build(
        RecallReadModel(asOf: asOf, subjects: const <RecallSubject>[]));
    expect(w.isEmpty, isTrue);
    expect(w.considered, 0);
  });
}
