import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/analytics/analysis.dart';
import 'package:medical_app/ai/analytics/analysis_engine.dart';
import 'package:medical_app/ai/analytics/analysis_parser.dart';
import 'package:medical_app/ai/schema/field_registry.dart';
import 'package:medical_app/core/db/app_database.dart';
import 'package:medical_app/core/db/db_types.dart';
import 'package:medical_app/core/db/schema.dart';
import 'package:medical_app/data/dao/analysis_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs the analysis SQL against a real SQLite database.
///
/// The engine is unit-tested against hand-written maps, which covers every
/// decision about what is honest to draw. What it cannot cover is the half in
/// between: whether the columns a registry entry names actually exist, whether
/// the two prefixes keep a `status` on the subject table apart from a `status`
/// on patients, and whether the join reaches the right rows. Those only fail
/// against a real schema, and they fail silently — a join that drops rows
/// produces a chart that looks fine.
void main() {
  sqfliteFfiInit();

  late Database db;
  late AnalysisDao dao;
  final now = DateTime(2026, 6, 15, 10);

  Future<void> insertPatient({
    required String id,
    String sex = 'female',
    String? city,
    String? district,
    DateTime? dob,
  }) async {
    await db.insert('patients', <String, Object?>{
      'id': id,
      'mrn': id,
      'family_name': 'Test',
      'given_name': id,
      'sex_at_birth': sex,
      'city': city,
      'district': district,
      'date_of_birth': dob == null ? null : toIsoDate(dob),
      'created_at': toEpoch(now),
      'updated_at': toEpoch(now),
    });
  }

  var rowSeq = 0;

  Future<void> insertVitals(
    String patientId, {
    int? systolic,
    double? bmi,
    DateTime? at,
    bool deleted = false,
  }) async {
    final recorded = at ?? now;
    await db.insert('vitals', <String, Object?>{
      'id': '$patientId-${rowSeq++}',
      'patient_id': patientId,
      'recorded_at': toEpoch(recorded),
      'systolic_bp': systolic,
      'bmi': bmi,
      'created_at': toEpoch(recorded),
      'updated_at': toEpoch(recorded),
      'deleted_at': deleted ? toEpoch(recorded) : null,
    });
  }

  Future<void> insertAppointment({
    required String id,
    required String patientId,
    required DateTime scheduled,
    String status = 'scheduled',
    DateTime? arrived,
    DateTime? started,
  }) async {
    await db.insert('appointments', <String, Object?>{
      'id': id,
      'patient_id': patientId,
      'clinic_id': 'clinic-1',
      'scheduled_at': toEpoch(scheduled),
      'status': status,
      'arrived_at': toEpochOrNull(arrived),
      'started_at': toEpochOrNull(started),
      'created_at': toEpoch(scheduled),
      'updated_at': toEpoch(scheduled),
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
    dao = AnalysisDao(AppDatabase.withHandle(db));
  });

  tearDown(() async => db.close());

  // The registry is a second description of the schema, and a second
  // description is a thing that goes stale. This is the check that it has not:
  // a renamed or dropped column fails here rather than at the moment a
  // clinician asks the question.
  test('every column the registry names exists in the schema', () async {
    for (final table in FieldRegistry.tables) {
      for (final field in table.fields) {
        final select = field.columns.map((c) => 't.$c').join(', ');
        await expectLater(
          db.rawQuery('SELECT $select FROM ${table.name} t LIMIT 1'),
          completes,
          reason: '${table.name}.${field.name} names a column that does not '
              'exist: ${field.columns.join(', ')}',
        );
      }
    }
  });

  test('a patient attribute joins onto a clinical table', () async {
    await insertPatient(id: 'p1', district: 'North');
    await insertPatient(id: 'p2', district: 'South');
    await insertVitals('p1', systolic: 160);
    await insertVitals('p1', systolic: 150);
    await insertVitals('p2', systolic: 120);

    final spec = AnalysisParser.parse('average blood pressure by district')!;
    final result = AnalysisEngine.run(spec, await dao.read(spec));

    expect(result.points.map((p) => p.label), containsAll(['North', 'South']));
    final north = result.points.firstWhere((p) => p.label == 'North');
    final south = result.points.firstWhere((p) => p.label == 'South');
    expect(north.value, 155);
    expect(north.n, 2);
    expect(south.value, 120);
  });

  // Nothing clinical is ever hard-deleted, so every query has to exclude the
  // tombstones. A chart that counts deleted rows silently overstates activity.
  test('soft-deleted rows are excluded on both sides of a join', () async {
    await insertPatient(id: 'p1', district: 'North');
    await insertVitals('p1', systolic: 200, deleted: true);
    await insertVitals('p1', systolic: 100);

    final spec = AnalysisParser.parse('average systolic by district')!;
    final result = AnalysisEngine.run(spec, await dao.read(spec));
    expect(result.points.single.value, 100);
  });

  // `status` exists on appointments and on nothing else here, but `created_at`
  // exists on both sides of every join. Without the two prefixes the patient
  // column would overwrite the subject's in the result map.
  test('a column name on both tables does not collide', () async {
    await insertPatient(id: 'p1', district: 'North', dob: DateTime(1990, 1, 1));
    await insertAppointment(
      id: 'a1',
      patientId: 'p1',
      scheduled: now,
      arrived: now,
      started: now.add(const Duration(minutes: 25)),
    );

    final spec = AnalysisParser.parse('average waiting time by district')!;
    final result = AnalysisEngine.run(spec, await dao.read(spec));
    expect(result.points.single.label, 'North');
    expect(result.points.single.value, 25);
  });

  test('a derived field computes from the columns it names', () async {
    // Five years apart, so the mean lands on a half whatever today's date is —
    // the derived age is computed against the real clock by design.
    await insertPatient(id: 'p1', dob: DateTime(1990, 6, 20));
    await insertPatient(id: 'p2', dob: DateTime(1995, 6, 20));
    await insertPatient(id: 'p3');

    final spec = AnalysisSpec(
      table: FieldRegistry.patients,
      aggregate: Aggregate.average,
      measure: FieldRegistry.patients.field('age'),
    );
    final result = AnalysisEngine.run(spec, await dao.read(spec));

    expect(result.points.single.value % 1, 0.5);
    // The patient with no date of birth is missing, not aged zero.
    expect(result.missing, 1);
  });

  test('a period filter narrows the rows read', () async {
    await insertPatient(id: 'p1');
    await insertVitals('p1', systolic: 100, at: DateTime(2026, 1, 5));
    await insertVitals('p1', systolic: 200, at: DateTime(2026, 6, 5));

    final spec = AnalysisParser.parse(
      'average systolic in the last 2 months',
      asOf: now,
    )!;
    final result = AnalysisEngine.run(spec, await dao.read(spec));
    expect(result.rowsRead, 1);
    expect(result.points.single.value, 200);
  });

  test('a breakdown over an empty table says nothing rather than zero',
      () async {
    final spec = AnalysisParser.parse('average systolic by district')!;
    final result = AnalysisEngine.run(spec, await dao.read(spec));
    expect(result.isEmpty, isTrue);
    expect(result.points, isEmpty);
  });
}
