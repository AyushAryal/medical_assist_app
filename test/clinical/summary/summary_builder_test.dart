import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/flags/clinical_flag.dart';
import 'package:medical_app/clinical/news2.dart';
import 'package:medical_app/clinical/summary/record_summary.dart';
import 'package:medical_app/clinical/summary/summary_builder.dart';

void main() {
  final asOf = DateTime(2026, 8, 29, 10, 0);

  ChartSnapshot snapshot({
    AllergyRecordState allergyState = AllergyRecordState.noneKnown,
    List<AllergyLine> allergies = const <AllergyLine>[],
    List<String> problems = const <String>[],
    List<String> medications = const <String>[],
    ObsView? obs,
    DateTime? lastSeen,
  }) =>
      ChartSnapshot(
        patientId: 'p',
        asOf: asOf,
        allergyState: allergyState,
        allergies: allergies,
        activeProblems: problems,
        currentMedications: medications,
        latestObs: obs,
        lastEncounterAt: lastSeen,
      );

  SummaryItem itemIn(RecordSummary s, String sectionKey) =>
      s.sections.firstWhere((sec) => sec.key == sectionKey).items.single;

  group('sections and order', () {
    test('builds a fixed clinical section order, allergies first', () {
      final s = SummaryBuilder.build(snapshot());
      expect(
        s.sections.map((sec) => sec.key),
        ['allergies', 'problems', 'medications', 'observations', 'activity'],
      );
    });
  });

  group('not-recorded is never normal', () {
    test('an unknown allergy status reads Not recorded, with a caution', () {
      final s = SummaryBuilder.build(
          snapshot(allergyState: AllergyRecordState.notRecorded));
      final item = itemIn(s, 'allergies');
      expect(item.value, 'Not recorded');
      expect(item.state, SummaryState.notRecorded);
      expect(item.severity, FlagSeverity.caution);
    });

    test('"no known allergies" is recorded, not a gap', () {
      final s = SummaryBuilder.build(
          snapshot(allergyState: AllergyRecordState.noneKnown));
      final item = itemIn(s, 'allergies');
      expect(item.value, 'No known allergies');
      expect(item.state, SummaryState.recorded);
      expect(item.severity, isNull);
    });

    test('an empty problem list is "None recorded", never a clean bill', () {
      final s = SummaryBuilder.build(snapshot(problems: const <String>[]));
      final item = itemIn(s, 'problems');
      expect(item.value, 'None recorded');
      expect(item.state, SummaryState.notRecorded);
    });

    test('no observations reads Not recorded with a caution', () {
      final s = SummaryBuilder.build(snapshot(obs: null));
      final item = itemIn(s, 'observations');
      expect(item.value, 'Not recorded');
      expect(item.state, SummaryState.notRecorded);
      expect(item.severity, FlagSeverity.caution);
    });

    test('notRecorded collects every gap', () {
      final s = SummaryBuilder.build(snapshot(
        allergyState: AllergyRecordState.notRecorded,
        problems: const <String>[],
        medications: const <String>[],
        obs: null,
        lastSeen: null,
      ));
      // allergies, problems, medications, observations, activity — all absent.
      expect(s.notRecorded, hasLength(5));
    });
  });

  group('present allergies', () {
    test('lists substances and flags critical when any is high severity', () {
      final s = SummaryBuilder.build(snapshot(
        allergyState: AllergyRecordState.present,
        allergies: const [
          (substance: 'Penicillin', severityLabel: 'severe', isHigh: true),
          (substance: 'Peanut', severityLabel: null, isHigh: false),
        ],
      ));
      final item = itemIn(s, 'allergies');
      expect(item.value, 'Penicillin (severe), Peanut');
      expect(item.state, SummaryState.recorded);
      expect(item.severity, FlagSeverity.critical);
    });

    test('flags caution when present but none high severity', () {
      final s = SummaryBuilder.build(snapshot(
        allergyState: AllergyRecordState.present,
        allergies: const [
          (substance: 'Latex', severityLabel: 'mild', isHigh: false),
        ],
      ));
      expect(itemIn(s, 'allergies').severity, FlagSeverity.caution);
    });
  });

  group('observations', () {
    test('a scored set shows the band, sourced with the timestamp', () {
      final s = SummaryBuilder.build(snapshot(
        obs: ObsView(
          recordedAt: DateTime(2026, 8, 29, 9, 5),
          risk: News2Risk.high,
          news2Total: 8,
        ),
      ));
      final item = itemIn(s, 'observations');
      expect(item.value, 'NEWS2 8 · High');
      expect(item.state, SummaryState.recorded);
      expect(item.severity, FlagSeverity.critical);
      expect(item.source, 'Observations · 2026-08-29 09:05');
    });

    test('an unscored-but-present set says why, still recorded', () {
      final s = SummaryBuilder.build(snapshot(
        obs: ObsView(
          recordedAt: DateTime(2026, 8, 29, 9, 5),
          unavailableReason: News2Unavailable.incompleteObservations,
        ),
      ));
      final item = itemIn(s, 'observations');
      expect(item.state, SummaryState.recorded);
      expect(item.value, contains('not scored'));
    });
  });

  group('last seen', () {
    test('no prior visits is a gap', () {
      final s = SummaryBuilder.build(snapshot(lastSeen: null));
      expect(itemIn(s, 'activity').state, SummaryState.notRecorded);
    });

    test('a prior visit is a recorded date', () {
      final s =
          SummaryBuilder.build(snapshot(lastSeen: DateTime(2026, 8, 20)));
      final item = itemIn(s, 'activity');
      expect(item.value, '2026-08-20');
      expect(item.state, SummaryState.recorded);
    });
  });
}
