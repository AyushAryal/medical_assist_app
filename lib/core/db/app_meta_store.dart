import 'package:sqflite_sqlcipher/sqflite.dart';

import 'app_database.dart';
import 'db_types.dart';

/// Key/value preferences that live *inside* the encrypted database rather than
/// in `SharedPreferences`.
///
/// The active clinic and the signing clinician's name are operational context
/// for a medical record. Neither belongs in a world-readable plist or XML file
/// alongside the app's other unencrypted settings.
class AppMetaStore {
  const AppMetaStore(this._database);

  final AppDatabase _database;
  static const String table = 'app_meta';

  static const String keyActiveClinic = 'active_clinic_id';
  static const String keyProviderName = 'provider_name';
  static const String keyDeviceId = 'device_id';
  static const String keyThemeMode = 'theme_mode';
  static const String keyOnboarded = 'onboarded';

  Future<String?> read(String key) async {
    if (!_database.isOpen) return null;
    final rows = await _database.db.query(
      table,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> write(String key, String? value) async {
    if (!_database.isOpen) return;
    await _database.db.insert(
      table,
      <String, Object?>{
        'key': key,
        'value': value,
        'updated_at': toEpoch(DateTime.now()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String?>> readAll(List<String> keys) async {
    return <String, String?>{
      for (final key in keys) key: await read(key),
    };
  }
}
