import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_types.dart';
import '../../core/utils/ids.dart';
import '../models/clinic.dart';

class ClinicDao {
  ClinicDao(this._database);

  final AppDatabase _database;
  static const String table = 'clinics';

  Database get _db => _database.db;

  Future<List<Clinic>> all({bool activeOnly = true}) async {
    final rows = await _db.query(
      table,
      where: activeOnly
          ? 'deleted_at IS NULL AND is_active = 1'
          : 'deleted_at IS NULL',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Clinic.fromMap).toList();
  }

  Future<Clinic?> byId(String id) async {
    final rows = await _db.query(
      table,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Clinic.fromMap(rows.first);
  }

  Future<Clinic> create({
    required String name,
    String? code,
    ClinicType type = ClinicType.clinic,
    String? addressLine,
    String? city,
    String? district,
    String? country,
    String? phone,
  }) async {
    final now = DateTime.now();
    final clinic = Clinic(
      id: newId(),
      name: name,
      code: code,
      type: type,
      addressLine: addressLine,
      city: city,
      district: district,
      country: country,
      phone: phone,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert(table, clinic.toMap());
    return clinic;
  }

  Future<void> update(Clinic clinic) async {
    await _db.update(
      table,
      clinic.toMap(),
      where: 'id = ?',
      whereArgs: [clinic.id],
    );
  }

  /// Soft delete. Historic encounters keep pointing at the clinic they
  /// happened in, which is why the row is never removed.
  Future<void> archive(String id) async {
    await _db.update(
      table,
      {
        'deleted_at': toEpoch(DateTime.now()),
        'is_active': 0,
        'sync_status': SyncStatus.pending,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> count() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE deleted_at IS NULL',
    );
    return (result.first['c'] as int?) ?? 0;
  }
}
