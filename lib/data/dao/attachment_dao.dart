import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_types.dart';
import '../models/attachment.dart';

class AttachmentDao {
  AttachmentDao(this._database);

  final AppDatabase _database;
  static const String table = 'attachments';

  Database get _db => _database.db;

  Future<List<Attachment>> forOwner(
    AttachmentOwner ownerType,
    String ownerId,
  ) async {
    final rows = await _db.query(
      table,
      where: 'owner_type = ? AND owner_id = ? AND deleted_at IS NULL',
      whereArgs: [ownerType.name, ownerId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Attachment.fromMap).toList();
  }

  Future<List<Attachment>> forPatient(String patientId, {int limit = 100}) async {
    final rows = await _db.query(
      table,
      where: 'patient_id = ? AND deleted_at IS NULL',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Attachment.fromMap).toList();
  }

  Future<Attachment> insert(Attachment attachment) async {
    await _db.insert(table, attachment.toMap());
    return attachment;
  }

  Future<void> update(Attachment attachment) async {
    await _db.update(
      table,
      attachment.toMap(),
      where: 'id = ?',
      whereArgs: [attachment.id],
    );
  }

  /// Marks the row deleted. The file on disk is removed separately by
  /// `AttachmentService`, which owns storage; keeping the two steps distinct
  /// means a failed unlink never leaves an orphaned database row.
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

  Future<int> totalBytes() async {
    final result = await _db.rawQuery(
      'SELECT SUM(size_bytes) AS s FROM $table WHERE deleted_at IS NULL',
    );
    return (result.first['s'] as int?) ?? 0;
  }
}
