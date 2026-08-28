import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_types.dart';
import '../models/smart_phrase_record.dart';

/// Reads and writes the user's text-expansion smart phrases.
class SmartPhraseDao {
  SmartPhraseDao(this._database);

  final AppDatabase _database;
  static const String table = 'smart_phrases';

  Database get _db => _database.db;

  /// All live phrases, seeded defaults and user additions together, ordered so
  /// the menu is stable — by trigger.
  Future<List<SmartPhraseRecord>> all() async {
    final rows = await _db.query(
      table,
      where: 'deleted_at IS NULL',
      orderBy: 'trigger COLLATE NOCASE ASC',
    );
    return rows.map(SmartPhraseRecord.fromMap).toList();
  }

  Future<void> upsert(SmartPhraseRecord record) async {
    await _db.insert(
      table,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Soft-delete, like everything else — a removed phrase should still sync as
  /// a deletion rather than silently reappearing from another device.
  Future<void> archive(String id) async {
    await _db.update(
      table,
      <String, Object?>{
        'deleted_at': toEpoch(DateTime.now()),
        'updated_at': toEpoch(DateTime.now()),
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
