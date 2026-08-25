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

/// The whole pipeline against a real database: question in, presentation out.
///
/// The unit tests hold each stage; what only this can hold is the *joints* —
/// that a ranking's folded rows really come back as tappable patients, that a
/// dashboard's tiles really are the same answers the questions get alone, and
/// that the interpreter ordering resolves the overlapping phrasings the way
/// the design says it does.
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

  Future<void> insertPatient(String id, {String? phone, DateTime? dob}) async {
    await db.insert('patients', <String, Object?>{
      'id': id,
      'mrn': 'M$id',
      'family_name': 'Fam$id',
      'given_name': 'Giv$id',
      'sex_at_birth': 'female',
      'phone': phone,
      'date_of_birth': dob == null ? null : toIsoDate(dob),
      'created_at': toEpoch(now),
      'updated_at': toEpoch(now),
    });
  }

  var rowSeq = 0;
  Future<void> insertVitals(
    String patientId, {
    int? news2,
    int? systolic,
    DateTime? at,
  }) async {
    await db.insert('vitals', <String, Object?>{
      'id': 'v${rowSeq++}',
      'patient_id': patientId,
      'recorded_at': toEpoch(at ?? now),
      'news2_score': news2,
      'systolic_bp': systolic,
      'created_at': toEpoch(at ?? now),
      'updated_at': toEpoch(at ?? now),
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

  test('a ranking folds readings to one tappable patient each', () async {
    await insertPatient('p1');
    await insertPatient('p2');
    // p1 deteriorating: three readings, worst 7. Row-ranking would put p1 in
    // the list three times and hide p2 entirely.
    await insertVitals('p1', news2: 3);
    await insertVitals('p1', news2: 7);
    await insertVitals('p1', news2: 5);
    await insertVitals('p2', news2: 6);

    final result = await ask('riskiest patients');
    final metric = result.presentation as MetricPresentation;

    expect(metric.rows.map((r) => r.patient.id), <String>['p1', 'p2']);
    expect(metric.rows.first.detail, contains('7'));
    // Both renderings offered: the list to act on, the table to read from.
    expect(metric.views, containsAll(<ResultView>[
      ResultView.list,
      ResultView.table,
    ]));
    // Coded logic end to end: no badge.
    expect(result.isGenerated, isFalse);
  });

  test('"patients with high bp" states the threshold it applied', () async {
    await insertPatient('p1');
    await insertPatient('p2');
    await insertVitals('p1', systolic: 152);
    await insertVitals('p2', systolic: 128);

    final result = await ask('patients with high bp');
    final metric = result.presentation as MetricPresentation;

    expect(metric.value, 1);
    expect(metric.rows.single.patient.id, 'p1');
    // The reading of "high" is stated, and stated as measurement not
    // diagnosis — the property the wording exists to protect.
    expect(result.presentation.headline, contains('140'));
    expect(result.presentation.headline.toLowerCase(),
        contains('not diagnoses'));
  });

  test('a directory question comes back as a table of contacts', () async {
    await insertPatient('p1', phone: '555-0101');
    await insertPatient('p2');

    final result = await ask('patients and their contact numbers');
    final metric = result.presentation as MetricPresentation;

    expect(metric.value, 2);
    expect(metric.columns, <String>['Phone']);
    // The table leads because columns were asked for…
    expect(metric.views.first, ResultView.table);
    // …a missing phone is an em-dash, not an invented value…
    expect(metric.cells, containsAll(<List<String>>[
      <String>['555-0101'],
      <String>['—'],
    ]));
  });

  test('the dashboard is composed of ordinary answers', () async {
    await insertPatient('p1');
    await insertVitals('p1', news2: 6);

    final result = await ask('clinic dashboard');
    final dashboard = result.presentation as DashboardPresentation;

    expect(dashboard.panels, hasLength(4));
    // Each tile is a real presentation from a real handler — the ranking tile
    // holds the same patient the direct question would return.
    final risk = dashboard.panels
        .firstWhere((p) => p.title.contains('warning'))
        .body as MetricPresentation;
    expect(risk.rows.single.patient.id, 'p1');
  });

  test('overlapping phrasings land on the interpreter the design says',
      () async {
    await insertPatient('p1', dob: DateTime(1990));
    await insertVitals('p1', systolic: 120);

    // A maximum is a number; a "who" is people. One word of difference.
    expect((await ask('highest systolic bp')).intent, isA<AnalysisIntent>());
    expect(
      (await ask('patients with the highest systolic bp')).intent,
      isA<RankIntent>(),
    );
    // And the cohort matcher keeps everything filter-shaped.
    expect((await ask('everyone on warfarin')).intent, isA<QueryIntent>());
  });
}
