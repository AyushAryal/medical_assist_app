import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/worklist/worklist.dart';

void main() {
  final asOf = DateTime(2026, 8, 29, 10, 0);

  WorklistEntry entry(String id, int rank) => WorklistEntry(
        patientId: id,
        rank: rank,
        reasons: const ['because'],
        provenance: const [ProvenanceRef(label: 'x')],
      );

  test('accepts a list where considered = included + excluded', () {
    final w = Worklist(
      id: 'w',
      title: 'W',
      asOf: asOf,
      entries: [entry('a', 1), entry('b', 2)],
      considered: 3,
      excluded: const [WorklistExclusion(patientId: 'c', reason: 'no clinic')],
    );
    expect(w.entries.length, 2);
    expect(w.excluded.length, 1);
  });

  test('rejects a list that silently drops a considered patient', () {
    expect(
      () => Worklist(
        id: 'w',
        title: 'W',
        asOf: asOf,
        entries: [entry('a', 1)],
        considered: 5, // looked at 5, listed 1, accounted for none of the rest
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
