import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/cohort/cohort_query.dart';
import 'package:medical_app/core/db/app_database.dart';
import 'package:medical_app/core/db/db_types.dart';
import 'package:medical_app/core/db/schema.dart';
import 'package:medical_app/data/dao/cohort_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs the real cohort SQL against a real SQLite database.
///
/// String assertions cannot tell well-formed SQL from *right* SQL, and this is
/// the one place in the app where wrong is invisible: a recall list that
/// silently misses three patients looks exactly like a correct one, and nobody
/// checks it, because the reason for running it is that nobody could assemble
/// it by hand. So these tests are about who is found and who is missed.
///
/// Plain SQLite rather than SQLCipher — encryption changes how bytes are
/// stored, not which rows a WHERE clause selects.
void main() {
  sqfliteFfiInit();

  late Database db;
  late CohortDao dao;
  final now = DateTime.now();

  Future<void> insertPatient({
    required String id,
    String family = 'Test',
    String given = 'Patient',
    String sex = 'female',
    DateTime? dob,
    DateTime? lastSeen,
    DateTime? deceased,
    String? clinicId,
  }) async {
    await db.insert('patients', <String, Object?>{
      'id': id,
      'mrn': id,
      'family_name': family,
      'given_name': given,
      'sex_at_birth': sex,
      'date_of_birth': dob == null ? null : toIsoDate(dob),
      'deceased_date': deceased == null ? null : toIsoDate(deceased),
      'primary_clinic_id': clinicId,
      'last_seen_at': toEpochOrNull(lastSeen),
      'created_at': toEpoch(now),
      'updated_at': toEpoch(now),
    });
  }

  Future<void> giveMedication(
    String patientId,
    String name, {
    String status = 'active',
  }) async {
    await db.insert('medications', <String, Object?>{
      'id': '$patientId-$name',
      'patient_id': patientId,
      'name': name,
      'status': status,
      'created_at': toEpoch(now),
      'updated_at': toEpoch(now),
    });
  }

  Future<void> giveProblem(
    String patientId,
    String display, {
    String status = 'active',
  }) async {
    await db.insert('problems', <String, Object?>{
      'id': '$patientId-$display',
      'patient_id': patientId,
      'display': display,
      'status': status,
      'created_at': toEpoch(now),
      'updated_at': toEpoch(now),
    });
  }

  Future<void> giveAllergy(String patientId, String substance) async {
    await db.insert('allergies', <String, Object?>{
      'id': '$patientId-$substance',
      'patient_id': patientId,
      'substance': substance,
      'status': 'active',
      'created_at': toEpoch(now),
      'updated_at': toEpoch(now),
    });
  }

  Future<void> giveEncounter(String patientId, DateTime at) async {
    await db.insert('encounters', <String, Object?>{
      'id': '$patientId-${at.microsecondsSinceEpoch}',
      'patient_id': patientId,
      'clinic_id': 'clinic-1',
      'type': 'follow_up',
      'status': 'signed',
      'started_at': toEpoch(at),
      'created_at': toEpoch(at),
      'updated_at': toEpoch(at),
    });
  }

  setUp(() async {
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
    dao = CohortDao(AppDatabase.withHandle(db));
  });

  tearDown(() async => db.close());

  group('recall by medication', () {
    setUp(() async {
      await insertPatient(id: 'p1', family: 'Plain');
      await giveMedication('p1', 'Warfarin');

      await insertPatient(id: 'p2', family: 'Dosed');
      // The case this whole design exists for: a dose in the name field must
      // not cause the patient to be missed from a recall.
      await giveMedication('p2', 'Warfarin 3mg');

      await insertPatient(id: 'p3', family: 'Lowercase');
      await giveMedication('p3', 'warfarin sodium');

      await insertPatient(id: 'p4', family: 'Stopped');
      await giveMedication('p4', 'Warfarin', status: 'stopped');

      await insertPatient(id: 'p5', family: 'Other');
      await giveMedication('p5', 'Metformin');
    });

    test('finds every active prescription regardless of dose or case', () async {
      final rows = await dao.patients(
        const CohortQuery(kind: CohortQueryKind.recall, medication: 'warfarin'),
      );

      expect(
        rows.map((r) => r.patient.id).toSet(),
        <String>{'p1', 'p2', 'p3'},
      );
    });

    test('excludes a stopped prescription', () async {
      final rows = await dao.patients(
        const CohortQuery(kind: CohortQueryKind.recall, medication: 'warfarin'),
      );
      expect(rows.map((r) => r.patient.id), isNot(contains('p4')));
    });

    test('the count agrees with the list', () async {
      // A count and a list that disagree destroys confidence in both.
      const query =
          CohortQuery(kind: CohortQueryKind.recall, medication: 'warfarin');
      expect(await dao.count(query), (await dao.patients(query)).length);
    });

    test('does not match a drug that merely contains the term', () async {
      await insertPatient(id: 'p6', family: 'Prefixed');
      await giveMedication('p6', 'Nowarfarin');

      final rows = await dao.patients(
        const CohortQuery(kind: CohortQueryKind.recall, medication: 'warfarin'),
      );
      expect(rows.map((r) => r.patient.id), isNot(contains('p6')));
    });

    test('an underscore in the term is a literal, not a wildcard', () async {
      await insertPatient(id: 'p7');
      await giveMedication('p7', 'co-trimoxazole');
      await insertPatient(id: 'p8');
      await giveMedication('p8', 'co_trimoxazole');

      final rows = await dao.patients(
        const CohortQuery(
          kind: CohortQueryKind.recall,
          medication: 'co_trimoxazole',
        ),
      );

      // Without escaping, `_` matches any character and this over-matches.
      // On a recall list, finding too much is as wrong as finding too little.
      expect(rows.map((r) => r.patient.id), <String>['p8']);
    });
  });

  group('recall by allergy', () {
    test('finds an allergy recorded with extra detail', () async {
      await insertPatient(id: 'a1');
      await giveAllergy('a1', 'Penicillin');
      await insertPatient(id: 'a2');
      await giveAllergy('a2', 'Penicillins');
      await insertPatient(id: 'a3');
      await giveAllergy('a3', 'Sulfa');

      final rows = await dao.patients(
        const CohortQuery(
          kind: CohortQueryKind.recall,
          allergy: 'penicillin',
        ),
      );
      expect(rows.map((r) => r.patient.id).toSet(), <String>{'a1', 'a2'});
    });
  });

  group('deceased patients', () {
    setUp(() async {
      await insertPatient(id: 'd1');
      await giveMedication('d1', 'Warfarin');
      await insertPatient(
        id: 'd2',
        deceased: now.subtract(const Duration(days: 30)),
      );
      await giveMedication('d2', 'Warfarin');
    });

    test('are excluded by default', () async {
      // A recall list that telephones the dead is not merely a data problem.
      final rows = await dao.patients(
        const CohortQuery(kind: CohortQueryKind.recall, medication: 'warfarin'),
      );
      expect(rows.map((r) => r.patient.id), <String>['d1']);
    });

    test('are included when explicitly asked for', () async {
      final rows = await dao.patients(
        const CohortQuery(
          kind: CohortQueryKind.recall,
          medication: 'warfarin',
          includeDeceased: true,
        ),
      );
      expect(rows.map((r) => r.patient.id).toSet(), <String>{'d1', 'd2'});
    });
  });

  group('overdue follow-up', () {
    setUp(() async {
      await insertPatient(
        id: 'o1',
        lastSeen: now.subtract(const Duration(days: 400)),
      );
      await giveProblem('o1', 'Diabetes mellitus');

      await insertPatient(
        id: 'o2',
        lastSeen: now.subtract(const Duration(days: 10)),
      );
      await giveProblem('o2', 'Diabetes mellitus');

      // Registered and never seen — precisely who this should surface.
      await insertPatient(id: 'o3');
      await giveProblem('o3', 'Diabetes mellitus');
    });

    test('finds the long-overdue and the never-seen', () async {
      final rows = await dao.patients(
        CohortQuery(
          kind: CohortQueryKind.overdue,
          problem: 'Diabetes mellitus',
          notSeenSince: now.subtract(const Duration(days: 180)),
        ),
      );

      expect(rows.map((r) => r.patient.id).toSet(), <String>{'o1', 'o3'});
    });

    test('a resolved problem does not keep someone on the list', () async {
      await insertPatient(id: 'o4');
      await giveProblem('o4', 'Diabetes mellitus', status: 'resolved');

      final rows = await dao.patients(
        CohortQuery(
          kind: CohortQueryKind.overdue,
          problem: 'Diabetes mellitus',
          notSeenSince: now.subtract(const Duration(days: 180)),
        ),
      );
      expect(rows.map((r) => r.patient.id), isNot(contains('o4')));
    });
  });

  group('age bands', () {
    setUp(() async {
      await insertPatient(
        id: 'baby',
        dob: DateTime(now.year, now.month - 6, 1),
      );
      await insertPatient(id: 'toddler', dob: _yearsAgo(now, 3));
      await insertPatient(id: 'child', dob: _yearsAgo(now, 8));
      await insertPatient(id: 'adult', dob: _yearsAgo(now, 40));
      await insertPatient(id: 'senior', dob: _yearsAgo(now, 70));
      await insertPatient(id: 'unknown-age');
    });

    test('under 5 includes infants and excludes older children', () async {
      final rows = await dao.patients(
        const CohortQuery(
          kind: CohortQueryKind.cohort,
          ageBand: AgeBand.under5,
        ),
      );
      expect(
        rows.map((r) => r.patient.id).toSet(),
        <String>{'baby', 'toddler'},
      );
    });

    test('over 65 selects only the eldest', () async {
      final rows = await dao.patients(
        const CohortQuery(
          kind: CohortQueryKind.cohort,
          ageBand: AgeBand.over65,
        ),
      );
      expect(rows.map((r) => r.patient.id), <String>['senior']);
    });

    test('a patient with no date of birth is left out of every band', () async {
      // Documented in the explanation sheet, and asserted here so it stays a
      // deliberate choice rather than becoming a silent omission.
      for (final band in AgeBand.values) {
        final rows = await dao.patients(
          CohortQuery(kind: CohortQueryKind.cohort, ageBand: band),
        );
        expect(
          rows.map((r) => r.patient.id),
          isNot(contains('unknown-age')),
          reason: 'band ${band.label}',
        );
      }
    });
  });

  group('activity counts', () {
    setUp(() async {
      await insertPatient(id: 'v1');
      await giveEncounter('v1', now.subtract(const Duration(days: 3)));
      await giveEncounter('v1', now.subtract(const Duration(days: 2)));
      await insertPatient(id: 'v2');
      await giveEncounter('v2', now.subtract(const Duration(days: 1)));
      await insertPatient(id: 'v3');
      await giveEncounter('v3', now.subtract(const Duration(days: 90)));
    });

    test('counts visits, not people', () async {
      // "How many did we see" is a workload question: someone seen twice is
      // two consultations' worth of work.
      final count = await dao.encounterCount(
        CohortQuery(
          kind: CohortQueryKind.activity,
          periodFrom: now.subtract(const Duration(days: 7)),
          periodTo: now.add(const Duration(days: 1)),
        ),
      );
      expect(count, 3);
    });

    test('respects the period boundaries', () async {
      final count = await dao.encounterCount(
        CohortQuery(
          kind: CohortQueryKind.activity,
          periodFrom: now.subtract(const Duration(days: 2, hours: 12)),
          periodTo: now.add(const Duration(days: 1)),
        ),
      );
      expect(count, 2);
    });

    test('a cohort filter narrows an activity count', () async {
      await giveProblem('v1', 'Asthma');

      final count = await dao.encounterCount(
        CohortQuery(
          kind: CohortQueryKind.activity,
          problem: 'Asthma',
          periodFrom: now.subtract(const Duration(days: 7)),
          periodTo: now.add(const Duration(days: 1)),
        ),
      );
      expect(count, 2, reason: 'only v1 has asthma, and v1 has two visits');
    });
  });

  group('name search', () {
    setUp(() async {
      await insertPatient(id: 'n1', family: 'Aryal', given: 'Sita');
      await insertPatient(id: 'n2', family: 'Adhikari', given: 'Ram');
      await insertPatient(id: 'n3', family: 'Basnet', given: 'Anita');
      await insertPatient(id: 'n4', family: 'Gurung', given: 'Bikash');
    });

    test('a prefix matches either name part', () async {
      // Someone asking for "names starting with A" does not know or care which
      // field the clinic filed it under, and transposed name fields are a
      // routine data-entry error.
      final rows = await dao.patients(
        const CohortQuery(
          kind: CohortQueryKind.recall,
          nameStartsWith: 'A',
        ),
      );
      expect(
        rows.map((r) => r.patient.id).toSet(),
        <String>{'n1', 'n2', 'n3'},
      );
    });

    test('a longer prefix narrows correctly', () async {
      final rows = await dao.patients(
        const CohortQuery(kind: CohortQueryKind.recall, nameStartsWith: 'Ary'),
      );
      expect(rows.map((r) => r.patient.id), <String>['n1']);
    });

    test('a prefix does not match mid-name', () async {
      final rows = await dao.patients(
        const CohortQuery(kind: CohortQueryKind.recall, nameStartsWith: 'ryal'),
      );
      expect(rows, isEmpty);
    });

    test('contains matches anywhere and is case-insensitive', () async {
      final rows = await dao.patients(
        const CohortQuery(kind: CohortQueryKind.recall, nameContains: 'ryal'),
      );
      expect(rows.map((r) => r.patient.id), <String>['n1']);
    });

    test('a percent sign in the term is a literal, not "everyone"', () async {
      await insertPatient(id: 'n5', family: '%Odd', given: 'Edge');

      final rows = await dao.patients(
        const CohortQuery(kind: CohortQueryKind.recall, nameStartsWith: '%'),
      );

      // Unescaped, this pattern would match every patient on the register and
      // present the whole list as though it were a filtered result.
      expect(rows.map((r) => r.patient.id), <String>['n5']);
    });

    test('an MRN matches exactly, not by prefix', () async {
      final rows = await dao.patients(
        const CohortQuery(kind: CohortQueryKind.recall, mrn: 'n1'),
      );
      expect(rows.map((r) => r.patient.id), <String>['n1']);
    });
  });

  group('appointments', () {
    Future<void> book(
      String patientId,
      DateTime at, {
      String status = 'scheduled',
    }) async {
      await db.insert('appointments', <String, Object?>{
        'id': '$patientId-${at.microsecondsSinceEpoch}',
        'patient_id': patientId,
        'clinic_id': 'clinic-1',
        'scheduled_at': toEpoch(at),
        'duration_minutes': 15,
        'type': 'follow_up',
        'status': status,
        'created_at': toEpoch(now),
        'updated_at': toEpoch(now),
      });
    }

    setUp(() async {
      await insertPatient(id: 'ap1');
      await book('ap1', now.add(const Duration(days: 2)));
      await book('ap1', now.subtract(const Duration(days: 2)),
          status: 'completed');
      await insertPatient(id: 'ap2');
      await book('ap2', now.add(const Duration(days: 3)), status: 'cancelled');
      await insertPatient(id: 'ap3');
      await book('ap3', now.subtract(const Duration(days: 40)),
          status: 'noShow');
    });

    test('counts bookings in a window', () async {
      final count = await dao.appointmentCount(
        CohortQuery(
          kind: CohortQueryKind.activity,
          entity: QueryEntity.appointments,
          periodFrom: now.subtract(const Duration(days: 7)),
          periodTo: now.add(const Duration(days: 7)),
        ),
      );
      expect(count, 3, reason: 'the 40-day-old one is outside the window');
    });

    test('counts what was booked, not what happened', () async {
      // A clinic with many non-attenders has very different numbers for the
      // two, and conflating them overstates activity.
      final booked = await dao.appointmentCount(
        CohortQuery(
          kind: CohortQueryKind.activity,
          entity: QueryEntity.appointments,
          periodFrom: now.subtract(const Duration(days: 60)),
          periodTo: now.add(const Duration(days: 7)),
        ),
      );
      final happened = await dao.encounterCount(
        CohortQuery(
          kind: CohortQueryKind.activity,
          periodFrom: now.subtract(const Duration(days: 60)),
          periodTo: now.add(const Duration(days: 7)),
        ),
      );
      expect(booked, 4);
      expect(happened, 0, reason: 'no encounters were created');
    });

    test('filters by status', () async {
      final cancelled = await dao.appointmentCount(
        const CohortQuery(
          kind: CohortQueryKind.activity,
          entity: QueryEntity.appointments,
          appointmentStatus: 'cancelled',
        ),
      );
      expect(cancelled, 1);
    });

    test('lists appointments with the patient resolved', () async {
      final rows = await dao.appointments(
        const CohortQuery(
          kind: CohortQueryKind.recall,
          entity: QueryEntity.appointments,
          appointmentStatus: 'noShow',
        ),
      );
      expect(rows, hasLength(1));
      expect(rows.first.patient.id, 'ap3');
      expect(rows.first.detail, 'noShow');
      expect(rows.first.lastSeen, isNotNull);
    });

    test('a patient filter narrows an appointment question', () async {
      await giveProblem('ap1', 'Diabetes mellitus');

      final count = await dao.appointmentCount(
        CohortQuery(
          kind: CohortQueryKind.activity,
          entity: QueryEntity.appointments,
          problem: 'Diabetes mellitus',
          periodFrom: now.subtract(const Duration(days: 7)),
          periodTo: now.add(const Duration(days: 7)),
        ),
      );
      expect(count, 2, reason: 'both of ap1 bookings, none of the others');
    });

    test('finds patients who have an appointment in a window', () async {
      // The same filter answered as a patient question rather than a booking
      // one — "who has an appointment this week", not "how many bookings".
      final rows = await dao.patients(
        CohortQuery(
          kind: CohortQueryKind.recall,
          entity: QueryEntity.appointments,
          periodFrom: now,
          periodTo: now.add(const Duration(days: 7)),
        ),
      );
      expect(rows.map((r) => r.patient.id).toSet(), <String>{'ap1', 'ap2'});
    });

    test('a booking for a deleted patient is not listed', () async {
      await db.update(
        'patients',
        <String, Object?>{'deleted_at': toEpoch(now)},
        where: 'id = ?',
        whereArgs: <Object?>['ap3'],
      );
      final rows = await dao.appointments(
        const CohortQuery(
          kind: CohortQueryKind.recall,
          entity: QueryEntity.appointments,
          appointmentStatus: 'noShow',
        ),
      );
      expect(rows, isEmpty);
    });
  });

  group('free-text mentions — the safety net', () {
    Future<void> writeNote(
      String patientId, {
      String? assessment,
      String? plan,
      String? complaint,
    }) async {
      final encounterId = '$patientId-enc';
      await db.insert('encounters', <String, Object?>{
        'id': encounterId,
        'patient_id': patientId,
        'clinic_id': 'clinic-1',
        'type': 'follow_up',
        'status': 'signed',
        'chief_complaint': complaint,
        'started_at': toEpoch(now),
        'created_at': toEpoch(now),
        'updated_at': toEpoch(now),
      });
      await db.insert('clinical_notes', <String, Object?>{
        'id': '$patientId-note',
        'patient_id': patientId,
        'encounter_id': encounterId,
        'assessment': assessment,
        'plan': plan,
        'status': 'signed',
        'created_at': toEpoch(now),
        'updated_at': toEpoch(now),
      });
    }

    test('finds a drug written in a note but never added to the list',
        () async {
      // The failure this exists to catch. Medication lists drift out of date
      // while the narrative stays rich, so the patient most likely to be
      // missed from a recall is exactly this one.
      await insertPatient(id: 'fx1', family: 'Missed');
      await writeNote('fx1', plan: 'Continue warfarin 3mg daily.');

      final mentions = await dao.mentions('warfarin');

      expect(mentions.map((m) => m.patient.id), <String>['fx1']);
      expect(mentions.first.field, 'Plan');
      expect(mentions.first.excerpt.toLowerCase(), contains('warfarin'));
    });

    test('a denial never puts someone on a recall list', () async {
      // The single most dangerous false positive available here.
      await insertPatient(id: 'fx2');
      await writeNote('fx2', assessment: 'No history of warfarin therapy.');
      await insertPatient(id: 'fx3');
      await writeNote('fx3', assessment: 'Patient denies warfarin use.');

      expect(await dao.mentions('warfarin'), isEmpty);
    });

    test('excludes patients already on the structured list', () async {
      // The point of the section is who was left out, not a second copy of
      // the answer.
      await insertPatient(id: 'fx4');
      await giveMedication('fx4', 'Warfarin');
      await writeNote('fx4', plan: 'Continue warfarin.');

      final mentions = await dao.mentions(
        'warfarin',
        excludePatientIds: <String>{'fx4'},
      );
      expect(mentions, isEmpty);
    });

    test('searches the presenting complaint too', () async {
      await insertPatient(id: 'fx5');
      await writeNote('fx5', complaint: 'Chest pain, on warfarin');

      final mentions = await dao.mentions('warfarin');
      expect(mentions.map((m) => m.patient.id), contains('fx5'));
    });

    test('one row per patient, however many times it appears', () async {
      await insertPatient(id: 'fx6');
      await writeNote(
        'fx6',
        assessment: 'Warfarin dose reviewed.',
        plan: 'Warfarin continued. Warfarin INR in 2 weeks.',
      );

      final mentions = await dao.mentions('warfarin');
      expect(mentions.where((m) => m.patient.id == 'fx6'), hasLength(1));
    });

    test('the excerpt carries enough context to judge the hit', () async {
      // "father takes warfarin" has to be dismissible without opening the
      // chart, which is the only reason this can be shown at all.
      await insertPatient(id: 'fx7');
      await writeNote(
        'fx7',
        assessment: 'Family history: father takes warfarin for AF.',
      );

      final mentions = await dao.mentions('warfarin');
      expect(mentions.first.excerpt, contains('father'));
    });

    test('a deceased patient does not appear', () async {
      await insertPatient(
        id: 'fx8',
        deceased: now.subtract(const Duration(days: 10)),
      );
      await writeNote('fx8', plan: 'Continue warfarin.');

      expect(await dao.mentions('warfarin'), isEmpty);
    });

    test('a deleted note is not searched', () async {
      await insertPatient(id: 'fx9');
      await writeNote('fx9', plan: 'Continue warfarin.');
      await db.update(
        'clinical_notes',
        <String, Object?>{'deleted_at': toEpoch(now)},
        where: 'patient_id = ?',
        whereArgs: <Object?>['fx9'],
      );

      expect(await dao.mentions('warfarin'), isEmpty);
    });

    test('wildcards in the term stay literal', () async {
      // With an empty ESCAPE clause this matched every note in the database
      // and presented the whole register as a set of hits.
      await insertPatient(id: 'fx10');
      await writeNote('fx10', plan: 'Started on metformin.');

      expect(await dao.mentions('%'), isEmpty);
      expect(await dao.mentions('_etformin'), isEmpty);
      expect(
        (await dao.mentions('metformin')).map((m) => m.patient.id),
        <String>['fx10'],
      );
    });

    test('the limit is respected', () async {
      for (var i = 0; i < 8; i++) {
        await insertPatient(id: 'many$i');
        await writeNote('many$i', plan: 'On warfarin.');
      }
      expect(await dao.mentions('warfarin', limit: 3), hasLength(3));
    });
  });

  test('a soft-deleted patient is never returned', () async {
    await insertPatient(id: 'gone');
    await giveMedication('gone', 'Warfarin');
    await db.update(
      'patients',
      <String, Object?>{'deleted_at': toEpoch(now)},
      where: 'id = ?',
      whereArgs: <Object?>['gone'],
    );

    final rows = await dao.patients(
      const CohortQuery(kind: CohortQueryKind.recall, medication: 'warfarin'),
    );
    expect(rows, isEmpty);
  });

  test('the display limit never changes the reported total', () async {
    for (var i = 0; i < 12; i++) {
      await insertPatient(id: 'm$i');
      await giveMedication('m$i', 'Warfarin');
    }
    const query =
        CohortQuery(kind: CohortQueryKind.recall, medication: 'warfarin');

    final rows = await dao.patients(query, limit: 5);
    expect(rows, hasLength(5));
    // A truncated list must never be mistaken for a complete one.
    expect(await dao.count(query), 12);
  });
}

DateTime _yearsAgo(DateTime from, int years) =>
    DateTime(from.year - years, from.month, from.day);
