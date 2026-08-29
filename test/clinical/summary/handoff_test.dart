import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/flags/clinical_flag.dart';
import 'package:medical_app/clinical/news2.dart';
import 'package:medical_app/clinical/summary/handoff.dart';
import 'package:medical_app/clinical/summary/record_summary.dart';
import 'package:medical_app/clinical/summary/summary_builder.dart';

void main() {
  final asOf = DateTime(2026, 8, 29, 10, 0);

  RecordSummary record({
    AllergyRecordState allergy = AllergyRecordState.noneKnown,
    List<String> problems = const ['Hypertension'],
    ObsView? obs,
  }) =>
      SummaryBuilder.build(ChartSnapshot(
        patientId: 'p',
        asOf: asOf,
        allergyState: allergy,
        activeProblems: problems,
        currentMedications: const ['Amlodipine 5 mg'],
        latestObs: obs,
        lastEncounterAt: DateTime(2026, 8, 1),
      ));

  HandoffInput input({
    String? complaint,
    List<String> concerns = const [],
    List<String> outstanding = const [],
    RecordSummary? rec,
  }) =>
      HandoffInput(
        patientId: 'p',
        asOf: asOf,
        identityLine: 'Jane Doe · 46y · F · MRN 001',
        record: rec ?? record(),
        presentingComplaint: complaint,
        concerns: concerns,
        outstanding: outstanding,
      );

  HandoffSection part(Handoff h, SbarPart p) =>
      h.sections.firstWhere((s) => s.part == p);

  test('produces the four SBAR parts in order', () {
    final h = HandoffBuilder.build(input());
    expect(h.sections.map((s) => s.part), [
      SbarPart.situation,
      SbarPart.background,
      SbarPart.assessment,
      SbarPart.recommendation,
    ]);
  });

  test('situation carries identity, complaint and latest score', () {
    final h = HandoffBuilder.build(input(
      complaint: 'chest pain',
      rec: record(
        obs: ObsView(
          recordedAt: DateTime(2026, 8, 29, 9, 30),
          risk: News2Risk.high,
          news2Total: 8,
        ),
      ),
    ));
    final lines = part(h, SbarPart.situation).lines.map((l) => l.text).toList();
    expect(lines[0], contains('Jane Doe'));
    expect(lines[1], contains('chest pain'));
    expect(lines[2], contains('NEWS2 8'));
  });

  test('a missing presenting complaint is a stated gap', () {
    final h = HandoffBuilder.build(input(complaint: null));
    final line = part(h, SbarPart.situation).lines[1];
    expect(line.state, SummaryState.notRecorded);
    expect(line.severity, FlagSeverity.caution);
  });

  test('background carries the record gaps through unchanged', () {
    final h = HandoffBuilder.build(
        input(rec: record(allergy: AllergyRecordState.notRecorded)));
    final allergyLine = part(h, SbarPart.background)
        .lines
        .firstWhere((l) => l.text.startsWith('Allergies'));
    expect(allergyLine.state, SummaryState.notRecorded);
  });

  test('assessment states the negative when nothing is concerning', () {
    final h = HandoffBuilder.build(input(concerns: const []));
    expect(part(h, SbarPart.assessment).lines.single.text,
        contains('No deteriorating'));
  });

  test('assessment lists concerns with a caution tone', () {
    final h = HandoffBuilder.build(input(concerns: const [
      'Respiratory rate rising over 3 sets',
      'Red flag: chest pain',
    ]));
    final lines = part(h, SbarPart.assessment).lines;
    expect(lines, hasLength(2));
    expect(lines.every((l) => l.severity == FlagSeverity.caution), isTrue);
  });

  test('recommendation lists outstanding tasks or states none', () {
    final none = HandoffBuilder.build(input(outstanding: const []));
    expect(part(none, SbarPart.recommendation).lines.single.text,
        'No outstanding tasks.');

    final some = HandoffBuilder.build(
        input(outstanding: const ['Sign the encounter note', 'Book review in 2 weeks']));
    expect(part(some, SbarPart.recommendation).lines, hasLength(2));
  });

  test('plainText renders a deterministic SBAR block', () {
    final h = HandoffBuilder.build(input(complaint: 'cough'));
    final text = h.plainText;
    expect(text, contains('SBAR handoff — Jane Doe'));
    expect(text, contains('S — Situation'));
    expect(text, contains('R — Recommendation'));
    // Deterministic: same input, same output.
    expect(HandoffBuilder.build(input(complaint: 'cough')).plainText, text);
  });
}
