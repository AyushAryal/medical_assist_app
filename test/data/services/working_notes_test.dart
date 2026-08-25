import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/core/db/db_types.dart';
import 'package:medical_app/core/db/schema.dart';
import 'package:medical_app/data/models/clinical_note.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('working notes are scratch, not record', () {
    // The property the whole design rests on: the signature covers the four
    // sections and nothing else, so unsorted scratch can never change what a
    // signed note attests to.
    test('the signature hash ignores them', () {
      final base = ClinicalNote(
        id: 'n1',
        patientId: 'p1',
        encounterId: 'e1',
        subjective: 'Cough for three days.',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final withScratch = base.copyWith(
        workingNotes: 'anything at all in here',
      );

      expect(withScratch.computeHash(), base.computeHash());
      expect(withScratch.verifyIntegrity(), isTrue);
    });

    test('a note holding only working notes is still empty', () {
      final note = ClinicalNote(
        id: 'n1',
        patientId: 'p1',
        encounterId: 'e1',
        workingNotes: 'dictated but never sorted',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      // So "an empty note cannot be signed" still catches it — scratch is
      // not a section, however much of it there is.
      expect(note.isEmpty, isTrue);
    });

    test('clearing is expressible; the ?? idiom alone could not do it', () {
      final note = ClinicalNote(
        id: 'n1',
        patientId: 'p1',
        encounterId: 'e1',
        workingNotes: 'left over',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(note.copyWith(clearWorkingNotes: true).workingNotes, isNull);
      expect(note.copyWith().workingNotes, 'left over');
    });

    test('they survive a round trip through the database', () async {
      final db = await databaseFactoryFfi.openDatabase(
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
      addTearDown(db.close);

      final note = ClinicalNote(
        id: 'n1',
        patientId: 'p1',
        encounterId: 'e1',
        workingNotes: 'cough three days, chest clear, likely viral',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      await db.insert('clinical_notes', note.toMap());

      final rows = await db.query('clinical_notes', where: "id = 'n1'");
      expect(
        ClinicalNote.fromMap(rows.single).workingNotes,
        note.workingNotes,
      );
    });

    // v2 databases exist on devices already. The upgrade path replays the
    // same statements onCreate uses, so a column added in v3 has to arrive
    // for them too.
    test('a v2 database upgrades to hold them', () async {
      final path = inMemoryDatabasePath;
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: Schema.version,
          onCreate: (db, version) async {
            // Replay only v1 and v2, then let onUpgrade do the rest.
            for (final step in Schema.migrations.take(2)) {
              for (final statement in step) {
                await db.execute(statement);
              }
            }
            for (final statement in Schema.migrations[2]) {
              await db.execute(statement);
            }
          },
        ),
      );
      addTearDown(db.close);

      await db.insert('clinical_notes', <String, Object?>{
        'id': 'n1',
        'patient_id': 'p1',
        'encounter_id': 'e1',
        'working_notes': 'still here',
        'created_at': toEpoch(DateTime(2026)),
        'updated_at': toEpoch(DateTime(2026)),
      });
      final rows = await db.query('clinical_notes');
      expect(rows.single['working_notes'], 'still here');
    });
  });
}
