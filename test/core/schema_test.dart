import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/core/db/schema.dart';

/// Migration-list invariants.
///
/// `AppDatabase.onCreate` replays indices `0..version-1` and `onUpgrade`
/// replays `oldVersion..newVersion-1`. If the version and the list ever
/// disagree, a fresh install and an upgraded install end up with different
/// schemas — which surfaces as "no such column" on someone else's device,
/// long after the change was made.
void main() {
  group('migrations', () {
    test('version matches the number of migration steps', () {
      expect(
        Schema.version,
        Schema.migrations.length,
        reason: 'Adding a migration list entry requires bumping '
            'Schema.version, and vice versa.',
      );
    });

    test('every step contains at least one statement', () {
      for (var i = 0; i < Schema.migrations.length; i++) {
        expect(
          Schema.migrations[i],
          isNotEmpty,
          reason: 'Migration step $i is empty.',
        );
      }
    });

    test('no statement is blank or accidentally terminated', () {
      for (final step in Schema.migrations) {
        for (final statement in step) {
          expect(statement.trim(), isNotEmpty);
          // sqflite executes one statement per call; a trailing semicolon is a
          // sign two statements were pasted into one string.
          expect(
            statement.trim().endsWith(';'),
            isFalse,
            reason: 'Statement should not be semicolon-terminated: '
                '${statement.substring(0, 40)}…',
          );
        }
      }
    });

    test('v1 creates the tables the app depends on', () {
      final v1 = Schema.migrations.first.join('\n').toUpperCase();
      for (final table in <String>[
        'PATIENTS',
        'CLINICS',
        'ENCOUNTERS',
        'VITALS',
        'CLINICAL_NOTES',
        'NOTE_AMENDMENTS',
        'ALLERGIES',
        'PROBLEMS',
        'MEDICATIONS',
        'ATTACHMENTS',
        'AUDIT_EVENTS',
        'SYNC_QUEUE',
        'APP_META',
      ]) {
        expect(
          v1.contains('CREATE TABLE $table'),
          isTrue,
          reason: '$table is missing from the v1 migration.',
        );
      }
    });

    test('v2 adds appointments without touching v1', () {
      expect(Schema.migrations.length, greaterThanOrEqualTo(2));
      final v2 = Schema.migrations[1].join('\n').toUpperCase();
      expect(v2.contains('CREATE TABLE APPOINTMENTS'), isTrue);

      // SQLite cannot drop or alter a column, so a migration that tries is a
      // migration that will fail on a real device.
      for (final step in Schema.migrations.skip(1)) {
        for (final statement in step) {
          final upper = statement.toUpperCase();
          expect(upper.contains('DROP TABLE'), isFalse,
              reason: 'Migrations must be additive.');
          expect(upper.contains('DROP COLUMN'), isFalse,
              reason: 'SQLite cannot drop columns.');
        }
      }
    });

    test('every clinical table carries the sync envelope', () {
      final v1 = Schema.migrations.first;
      final clinicalTables = v1.where((s) =>
          s.toUpperCase().contains('CREATE TABLE') &&
          !s.toUpperCase().contains('AUDIT_EVENTS') &&
          !s.toUpperCase().contains('SYNC_QUEUE') &&
          !s.toUpperCase().contains('APP_META') &&
          !s.toUpperCase().contains('NOTE_AMENDMENTS'));

      for (final table in clinicalTables) {
        for (final column in <String>[
          'created_at',
          'updated_at',
          'deleted_at',
          'revision',
          'sync_status',
        ]) {
          expect(
            table.contains(column),
            isTrue,
            reason: 'A clinical table is missing $column:\n'
                '${table.trim().split('\n').first}',
          );
        }
      }
    });
  });
}
