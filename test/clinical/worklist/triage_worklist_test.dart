import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/flags/clinical_flag.dart';
import 'package:medical_app/clinical/news2.dart';
import 'package:medical_app/clinical/worklist/triage_worklist.dart';
import 'package:medical_app/clinical/worklist/worklist.dart';

/// The board's ordering is a safety contract, so every rule in it is pinned.
void main() {
  final asOf = DateTime(2026, 8, 29, 10, 0);

  TriageSubject scored({
    required String id,
    required News2Risk risk,
    int total = 0,
    Duration waited = const Duration(minutes: 10),
    String? mrn,
    List<ClinicalFlag> flags = const <ClinicalFlag>[],
  }) =>
      TriageSubject(
        patientId: id,
        mrn: mrn ?? id,
        displayName: id,
        arrivedAt: asOf.subtract(waited),
        risk: risk,
        unavailableReason: null,
        news2Total: total,
        vitalsRecordedAt: asOf.subtract(waited),
        vitalsRecordId: 'v-$id',
        flags: flags,
      );

  TriageSubject notScored({
    required String id,
    News2Unavailable reason = News2Unavailable.incompleteObservations,
    Duration waited = const Duration(minutes: 10),
    String? mrn,
    List<ClinicalFlag> flags = const <ClinicalFlag>[],
  }) =>
      TriageSubject(
        patientId: id,
        mrn: mrn ?? id,
        displayName: id,
        arrivedAt: asOf.subtract(waited),
        risk: null,
        unavailableReason: reason,
        flags: flags,
      );

  ClinicalFlag redFlag(String id) => ClinicalFlag(
        subjectId: id,
        kind: FlagKind.redFlag,
        severity: FlagSeverity.critical,
        title: 'Chest pain',
        reason: 'Chest pain — consider cardiac cause',
        source: 'Note',
      );

  List<String> order(Worklist w) => w.entries.map((e) => e.patientId).toList();

  group('band ordering', () {
    test('sorts high → medium → lowMedium → low', () {
      final w = TriageWorklist.build(TriageReadModel(asOf: asOf, subjects: [
        scored(id: 'low', risk: News2Risk.low),
        scored(id: 'high', risk: News2Risk.high),
        scored(id: 'lowMed', risk: News2Risk.lowMedium),
        scored(id: 'med', risk: News2Risk.medium),
      ]));
      expect(order(w), ['high', 'med', 'lowMed', 'low']);
    });
  });

  group('not-scored patients are never treated as low risk', () {
    test('a not-scored patient outranks measured low and low-medium', () {
      final w = TriageWorklist.build(TriageReadModel(asOf: asOf, subjects: [
        scored(id: 'low', risk: News2Risk.low),
        scored(id: 'lowMed', risk: News2Risk.lowMedium),
        notScored(id: 'unknown'),
      ]));
      // Unknown sits above both measured-reassuring bands.
      expect(order(w), ['unknown', 'lowMed', 'low']);
    });

    test('but a confirmed medium/high emergency still outranks unknown', () {
      final w = TriageWorklist.build(TriageReadModel(asOf: asOf, subjects: [
        notScored(id: 'unknown'),
        scored(id: 'high', risk: News2Risk.high),
        scored(id: 'med', risk: News2Risk.medium),
      ]));
      expect(order(w), ['high', 'med', 'unknown']);
    });

    test('not-scored entries are grouped apart, never given a band', () {
      final w = TriageWorklist.build(TriageReadModel(asOf: asOf, subjects: [
        notScored(id: 'unknown'),
        scored(id: 'low', risk: News2Risk.low),
      ]));
      final unknown = w.entries.firstWhere((e) => e.patientId == 'unknown');
      final low = w.entries.firstWhere((e) => e.patientId == 'low');
      expect(unknown.group, TriageGroup.needsObs);
      expect(low.group, TriageGroup.attention);
      expect(unknown.reasons.first, contains('Risk unknown'));
    });

    test('a not-scored patient with a red flag is pulled into attention', () {
      final w = TriageWorklist.build(TriageReadModel(asOf: asOf, subjects: [
        notScored(id: 'plain'),
        notScored(id: 'flagged', flags: [redFlag('flagged')]),
      ]));
      final flagged = w.entries.firstWhere((e) => e.patientId == 'flagged');
      expect(flagged.group, TriageGroup.attention);
      // And it leads its tier.
      expect(order(w).first, 'flagged');
    });
  });

  group('within a band', () {
    test('a critical flag is seen before one without', () {
      final w = TriageWorklist.build(TriageReadModel(asOf: asOf, subjects: [
        scored(id: 'calm', risk: News2Risk.medium, waited: const Duration(hours: 1)),
        scored(id: 'flagged', risk: News2Risk.medium, flags: [redFlag('flagged')]),
      ]));
      // Flagged wins despite a shorter wait.
      expect(order(w), ['flagged', 'calm']);
    });

    test('then longest wait first', () {
      final w = TriageWorklist.build(TriageReadModel(asOf: asOf, subjects: [
        scored(id: 'short', risk: News2Risk.low, waited: const Duration(minutes: 5)),
        scored(id: 'long', risk: News2Risk.low, waited: const Duration(minutes: 55)),
        scored(id: 'mid', risk: News2Risk.low, waited: const Duration(minutes: 30)),
      ]));
      expect(order(w), ['long', 'mid', 'short']);
    });

    test('ties break by MRN, giving one fixed total order', () {
      final t = const Duration(minutes: 20);
      final w = TriageWorklist.build(TriageReadModel(asOf: asOf, subjects: [
        scored(id: 'c', risk: News2Risk.low, waited: t, mrn: '003'),
        scored(id: 'a', risk: News2Risk.low, waited: t, mrn: '001'),
        scored(id: 'b', risk: News2Risk.low, waited: t, mrn: '002'),
      ]));
      expect(order(w), ['a', 'b', 'c']);
    });
  });

  group('determinism', () {
    test('the same snapshot yields the same order, regardless of input order', () {
      final subjects = [
        scored(id: 'high', risk: News2Risk.high, waited: const Duration(minutes: 3)),
        notScored(id: 'unknown', waited: const Duration(minutes: 40)),
        scored(id: 'low1', risk: News2Risk.low, waited: const Duration(minutes: 50), mrn: '010'),
        scored(id: 'low2', risk: News2Risk.low, waited: const Duration(minutes: 50), mrn: '020'),
        scored(id: 'med', risk: News2Risk.medium, waited: const Duration(minutes: 1)),
      ];
      final forward =
          order(TriageWorklist.build(TriageReadModel(asOf: asOf, subjects: subjects)));
      final reversed = order(TriageWorklist.build(
          TriageReadModel(asOf: asOf, subjects: subjects.reversed.toList())));
      expect(forward, reversed);
      expect(forward, ['high', 'med', 'unknown', 'low1', 'low2']);
    });
  });

  group('completeness', () {
    test('every waiting patient appears exactly once; nothing excluded', () {
      final subjects = [
        scored(id: 'a', risk: News2Risk.high),
        scored(id: 'b', risk: News2Risk.low),
        notScored(id: 'c'),
      ];
      final w =
          TriageWorklist.build(TriageReadModel(asOf: asOf, subjects: subjects));
      expect(w.considered, 3);
      expect(w.entries.length, 3);
      expect(w.excluded, isEmpty);
      expect(w.entries.map((e) => e.patientId).toSet(), {'a', 'b', 'c'});
      expect(w.entries.map((e) => e.rank), [1, 2, 3]);
    });

    test('an empty board is empty, not an error', () {
      final w = TriageWorklist.build(
          TriageReadModel(asOf: asOf, subjects: const <TriageSubject>[]));
      expect(w.isEmpty, isTrue);
      expect(w.considered, 0);
      expect(w.entries, isEmpty);
    });
  });

  group('every entry explains itself', () {
    test('reasons and provenance are present on all entries', () {
      final w = TriageWorklist.build(TriageReadModel(asOf: asOf, subjects: [
        scored(id: 'a', risk: News2Risk.high, total: 8, waited: const Duration(minutes: 42)),
        notScored(id: 'b'),
      ]));
      for (final e in w.entries) {
        expect(e.reasons, isNotEmpty);
        expect(e.provenance, isNotEmpty);
        expect(e.provenance.first.label, 'Arrival');
      }
      final a = w.entries.firstWhere((e) => e.patientId == 'a');
      expect(a.reasons, contains('NEWS2 8 (high)'));
      expect(a.reasons, contains('waiting 42 min'));
    });
  });

  group('fromObservations factory runs the shared calculator', () {
    test('scores a valid adult observation set', () {
      final s = TriageSubject.fromObservations(
        patientId: 'p',
        mrn: '001',
        displayName: 'p',
        arrivedAt: asOf.subtract(const Duration(minutes: 5)),
        ageYears: 40,
        isPregnant: false,
        observations: const News2Input(
          respiratoryRate: 28, // 3
          spo2: 91, // 3
          onOxygen: true, // 2
          systolicBp: 100, // 2
          heartRate: 120, // 2
          consciousness: Consciousness.alert,
          temperatureC: 37.0,
        ),
      );
      expect(s.isScored, isTrue);
      expect(s.risk, News2Risk.high);
      expect(s.news2Total, greaterThanOrEqualTo(7));
    });

    test('a child is out of scope, not scored', () {
      final s = TriageSubject.fromObservations(
        patientId: 'p',
        mrn: '001',
        displayName: 'p',
        arrivedAt: asOf,
        ageYears: 8,
        isPregnant: false,
        observations: const News2Input(
          respiratoryRate: 20,
          spo2: 98,
          systolicBp: 120,
          heartRate: 80,
          consciousness: Consciousness.alert,
          temperatureC: 37.0,
        ),
      );
      expect(s.isScored, isFalse);
      expect(s.unavailableReason, News2Unavailable.ageOutOfScope);
    });

    test('no observations at all is incomplete, not zero', () {
      final s = TriageSubject.fromObservations(
        patientId: 'p',
        mrn: '001',
        displayName: 'p',
        arrivedAt: asOf,
        ageYears: 40,
        isPregnant: false,
        observations: null,
      );
      expect(s.isScored, isFalse);
      expect(s.unavailableReason, News2Unavailable.incompleteObservations);
    });
  });
}
