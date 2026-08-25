import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/assist_request.dart';
import 'package:medical_app/ai/intent.dart';
import 'package:medical_app/ai/pipeline.dart';
import 'package:medical_app/ai/presentation.dart';
import 'package:medical_app/core/audit/audit_service.dart';
import 'package:medical_app/core/db/app_database.dart';
import 'package:medical_app/core/db/db_types.dart';
import 'package:medical_app/core/db/schema.dart';
import 'package:medical_app/core/modules/entitlements.dart';
import 'package:medical_app/data/repositories/clinical_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The pipeline as a dialogue: one thread, several turns, state carried.
///
/// These are the tests that keep the assistant a conversation rather than a
/// search box that forgets. Each scenario is two or three turns because the
/// property under test *is* the relationship between turns — no single-ask
/// test can hold it.
void main() {
  sqfliteFfiInit();

  late Database db;
  late AssistPipeline pipeline;
  final now = DateTime(2026, 8, 24, 10);

  Future<AssistResult> ask(String text) => pipeline.ask(AssistRequest(
        text: text,
        source: RequestSource.typed,
        actor: 'Dr Test',
        asOf: now,
      ));

  var rowSeq = 0;
  Future<void> insertPatient(
    String id, {
    String sex = 'female',
    DateTime? dob,
    String? onDrug,
  }) async {
    await db.insert('patients', <String, Object?>{
      'id': id,
      'mrn': 'M$id',
      'family_name': 'Fam$id',
      'given_name': 'Giv$id',
      'sex_at_birth': sex,
      'date_of_birth': dob == null ? null : toIsoDate(dob),
      'created_at': toEpoch(now),
      'updated_at': toEpoch(now),
    });
    if (onDrug != null) {
      await db.insert('medications', <String, Object?>{
        'id': 'm${rowSeq++}',
        'patient_id': id,
        'name': onDrug,
        'status': 'active',
        'created_at': toEpoch(now),
        'updated_at': toEpoch(now),
      });
    }
  }

  Future<void> insertVitals(String patientId, {int? news2}) async {
    await db.insert('vitals', <String, Object?>{
      'id': 'v${rowSeq++}',
      'patient_id': patientId,
      'recorded_at': toEpoch(now),
      'news2_score': news2,
      'created_at': toEpoch(now),
      'updated_at': toEpoch(now),
    });
  }

  setUp(() async {
    rowSeq = 0;
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: Schema.version,
        onCreate: (db, version) async {
          for (final step in Schema.migrations) {
            for (final statement in step) {
              await db.execute(statement);
            }
          }
        },
      ),
    );
    final database = AppDatabase.withHandle(db);
    pipeline = AssistPipeline(
      repository: ClinicalRepository.wire(
        database: database,
        audit: AuditService(database),
      ),
      entitlements: Entitlements(),
    );
  });

  tearDown(() async => db.close());

  test('"only the women" narrows the standing cohort, not the register',
      () async {
    await insertPatient('p1', sex: 'female', onDrug: 'Warfarin');
    await insertPatient('p2', sex: 'male', onDrug: 'Warfarin');
    await insertPatient('p3', sex: 'female'); // not on warfarin

    await ask('everyone on warfarin');
    final result = await ask('only the women');

    final intent = result.intent as QueryIntent;
    // Both filters, merged: the drug from turn one, the sex from turn two.
    expect(intent.query.medication, isNotNull);
    expect(intent.query.sexAtBirth, 'female');
    final metric = result.presentation as MetricPresentation;
    expect(metric.rows.single.patient.id, 'p1',
        reason: 'p3 is female but not on warfarin; p2 is on it but male');
    // The trail says what happened, so the merge is arguable.
    expect(
      result.provenance.steps.map((s) => s.stage),
      contains('context'),
    );
  });

  test('"what about visits" keeps the period and swaps the table', () async {
    await ask('appointments this month');
    final result = await ask('what about visits');

    final intent = result.intent as QueryIntent;
    expect(intent.query.entity.name, 'visits');
    expect(intent.query.periodFrom, DateTime(2026, 8),
        reason: 'the month travelled across the table swap');
  });

  test('a chart re-grains mid-conversation', () async {
    await ask('average systolic bp per week');
    final result = await ask('per month instead');

    final intent = result.intent as AnalysisIntent;
    expect(intent.spec.bucket.name, 'month');
    expect(intent.spec.measure?.name, 'systolic_bp',
        reason: 'the measure survives the re-grain');
  });

  test('a ranking narrows by demographics and resizes', () async {
    await insertPatient('p1', sex: 'female');
    await insertPatient('p2', sex: 'male');
    await insertVitals('p1', news2: 6);
    await insertVitals('p2', news2: 9);

    await ask('riskiest patients');
    final narrowed = await ask('just the women');
    final metric = narrowed.presentation as MetricPresentation;
    expect(metric.rows.single.patient.id, 'p1',
        reason: 'p2 scores higher but is excluded by the narrowing');

    final resized = await ask('top 3');
    expect((resized.intent as RankIntent).spec.limit, 3);
    expect((resized.intent as RankIntent).spec.sexAtBirth, 'female',
        reason: 'refinements accumulate until the topic changes');
  });

  test('a full new question changes the subject cleanly', () async {
    await insertPatient('p1', onDrug: 'Warfarin');
    await ask('everyone on warfarin');
    final result = await ask('unsigned notes');

    final intent = result.intent as QueryIntent;
    expect(intent.query.entity.name, 'notes');
    expect(intent.query.medication, isNull,
        reason: 'no marker, fully-formed question: the old filters must not '
            'leak into it');
  });

  test('a half-understood question is asked back, and a tap answers it',
      () async {
    await insertPatient('p1');
    await insertVitals('p1', news2: 4);

    final result = await ask('average pressure levels of everyone');
    final clarify = result.presentation as ClarifyPresentation;
    expect(clarify.options, isNotEmpty);
    expect(
      clarify.options.map((o) => o.label.toLowerCase()).join(' '),
      contains('bp'),
      reason: '"pressure" points at blood pressure',
    );

    // Tapping an option runs a real question end to end.
    final answered = await ask(clarify.options.first.question);
    expect(answered.intent, isA<AnalysisIntent>());
  });

  test('colloquial phrasing lands on the canonical question, visibly',
      () async {
    await insertPatient('p1');
    await insertVitals('p1', news2: 7);

    final result = await ask('who should I worry about?');
    expect(result.intent, isA<RankIntent>());
    expect(
      result.provenance.steps.map((s) => s.stage),
      contains('reword'),
      reason: 'the rewrite must be on the record, not silent',
    );
  });

  test('recap replays the conversation as tappable questions', () async {
    await insertPatient('p1', onDrug: 'Warfarin');
    await ask('everyone on warfarin');
    await ask('appointments today');

    final result = await ask('recap');
    final message = result.presentation as MessagePresentation;
    expect(message.suggestions, contains('everyone on warfarin'));
    expect(message.suggestions, contains('appointments today'));
  });

  test('starting afresh forgets, and the next fragment stands alone',
      () async {
    await insertPatient('p1', onDrug: 'Warfarin');
    await ask('everyone on warfarin');
    pipeline.startAfresh();

    final result = await ask('only the women');
    // No standing question: read literally as the register's women.
    expect((result.intent as QueryIntent).query.medication, isNull);
  });
}
