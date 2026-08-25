import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_types.dart';
import '../models/encounter.dart';

class EncounterDao {
  EncounterDao(this._database);

  final AppDatabase _database;
  static const String table = 'encounters';

  Database get _db => _database.db;

  Future<Encounter?> byId(String id) async {
    final rows = await _db.query(
      table,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Encounter.fromMap(rows.first);
  }

  Future<List<Encounter>> forPatient(String patientId, {int limit = 100}) async {
    final rows = await _db.query(
      table,
      where: 'patient_id = ? AND deleted_at IS NULL',
      whereArgs: [patientId],
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(Encounter.fromMap).toList();
  }

  Future<Encounter?> mostRecentForPatient(String patientId) async {
    final rows = await _db.query(
      table,
      where: 'patient_id = ? AND deleted_at IS NULL',
      whereArgs: [patientId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Encounter.fromMap(rows.first);
  }

  /// Encounters that started within the local calendar day.
  Future<List<Encounter>> forDay(DateTime day, {String? clinicId}) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final where = StringBuffer(
      'deleted_at IS NULL AND started_at >= ? AND started_at < ?',
    );
    final args = <Object?>[toEpoch(start), toEpoch(end)];
    if (clinicId != null) {
      where.write(' AND clinic_id = ?');
      args.add(clinicId);
    }

    final rows = await _db.query(
      table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'started_at DESC',
    );
    return rows.map(Encounter.fromMap).toList();
  }

  /// Encounters still open or unsigned — the clinician's outstanding work.
  /// This drives the dashboard's most important number.
  Future<List<Encounter>> openOrUnsigned({int limit = 100}) async {
    final rows = await _db.query(
      table,
      where: 'deleted_at IS NULL AND status IN (?, ?, ?)',
      whereArgs: [
        EncounterStatus.draft.name,
        EncounterStatus.inProgress.name,
        EncounterStatus.completed.name,
      ],
      orderBy: 'started_at ASC',
      limit: limit,
    );
    return rows.map(Encounter.fromMap).toList();
  }

  /// Follow-ups due on or before [through], excluding patients already seen
  /// since the appointment was set.
  Future<List<Encounter>> followUpsDue(DateTime through) async {
    final rows = await _db.query(
      table,
      where: 'deleted_at IS NULL AND follow_up_date IS NOT NULL '
          'AND follow_up_date <= ?',
      whereArgs: [toIsoDate(through)],
      orderBy: 'follow_up_date ASC',
    );
    return rows.map(Encounter.fromMap).toList();
  }

  Future<Encounter> insert(Encounter encounter) async {
    await _db.insert(table, encounter.toMap());
    return encounter;
  }

  Future<void> update(Encounter encounter) async {
    await _db.update(
      table,
      encounter.toMap(),
      where: 'id = ?',
      whereArgs: [encounter.id],
    );
  }

  Future<Map<EncounterStatus, int>> countsByStatus() async {
    final rows = await _db.rawQuery(
      'SELECT status, COUNT(*) AS c FROM $table '
      'WHERE deleted_at IS NULL GROUP BY status',
    );
    return <EncounterStatus, int>{
      for (final row in rows)
        EncounterStatusX.parse(row['status'] as String?):
            (row['c'] as int?) ?? 0,
    };
  }
}
