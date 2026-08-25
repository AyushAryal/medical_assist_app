import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_types.dart';
import '../models/vitals_record.dart';

class VitalsDao {
  VitalsDao(this._database);

  final AppDatabase _database;
  static const String table = 'vitals';

  Database get _db => _database.db;

  Future<VitalsRecord?> byId(String id) async {
    final rows = await _db.query(
      table,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : VitalsRecord.fromMap(rows.first);
  }

  /// Newest first — the trend view and the "compare with last" affordance both
  /// read from this.
  Future<List<VitalsRecord>> forPatient(String patientId, {int limit = 50}) async {
    final rows = await _db.query(
      table,
      where: 'patient_id = ? AND deleted_at IS NULL',
      whereArgs: [patientId],
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
    return rows.map(VitalsRecord.fromMap).toList();
  }

  Future<VitalsRecord?> latestForPatient(String patientId) async {
    final rows = await _db.query(
      table,
      where: 'patient_id = ? AND deleted_at IS NULL',
      whereArgs: [patientId],
      orderBy: 'recorded_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : VitalsRecord.fromMap(rows.first);
  }

  Future<List<VitalsRecord>> forEncounter(String encounterId) async {
    final rows = await _db.query(
      table,
      where: 'encounter_id = ? AND deleted_at IS NULL',
      whereArgs: [encounterId],
      orderBy: 'recorded_at DESC',
    );
    return rows.map(VitalsRecord.fromMap).toList();
  }

  /// Observation sets recorded today that carry a medium or high NEWS2.
  /// Surfaced on the dashboard as the "needs a second look" list.
  Future<List<VitalsRecord>> elevatedToday(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await _db.query(
      table,
      where: 'deleted_at IS NULL AND recorded_at >= ? AND recorded_at < ? '
          'AND news2_score >= 5',
      whereArgs: [toEpoch(start), toEpoch(end)],
      orderBy: 'news2_score DESC, recorded_at DESC',
    );
    return rows.map(VitalsRecord.fromMap).toList();
  }

  Future<int> countForDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table '
      'WHERE deleted_at IS NULL AND recorded_at >= ? AND recorded_at < ?',
      [toEpoch(start), toEpoch(end)],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<VitalsRecord> insert(VitalsRecord record) async {
    await _db.insert(table, record.toMap());
    return record;
  }

  Future<void> update(VitalsRecord record) async {
    await _db.update(
      table,
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<void> archive(String id) async {
    await _db.update(
      table,
      {
        'deleted_at': toEpoch(DateTime.now()),
        'sync_status': SyncStatus.pending,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
