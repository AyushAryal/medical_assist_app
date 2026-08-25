import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../security/db_key_manager.dart';
import 'schema.dart';

/// Opens and owns the single SQLCipher-encrypted database handle.
///
/// The file itself is AES-256 encrypted page-by-page; without the key from the
/// platform keystore it is indistinguishable from random bytes, so a pulled
/// device image or a rooted-device file copy yields nothing.
class AppDatabase {
  AppDatabase(this._keyManager);

  /// Wraps an already-open handle.
  ///
  /// Exists so the query layer can be tested against a real SQLite database
  /// rather than only having its SQL asserted as strings. That matters most for
  /// the cohort queries: a recall list that silently misses three patients is
  /// indistinguishable from a correct one, and string assertions cannot tell
  /// the difference between SQL that is well-formed and SQL that is right.
  ///
  /// Never used by the app itself — production always goes through [open],
  /// which is the only path that supplies the encryption key.
  @visibleForTesting
  AppDatabase.withHandle(Database handle) : _keyManager = null, _db = handle;

  final DbKeyManager? _keyManager;
  Database? _db;

  static const String fileName = 'clinical.enc.db';

  Database get db {
    final handle = _db;
    if (handle == null) {
      throw StateError('AppDatabase.open() must be awaited before use');
    }
    return handle;
  }

  bool get isOpen => _db != null;

  Future<Database> open() async {
    final existing = _db;
    if (existing != null) return existing;

    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, fileName);
    final keyManager = _keyManager;
    if (keyManager == null) {
      throw StateError(
        'This AppDatabase wraps a handle supplied for testing and cannot open '
        'an encrypted database.',
      );
    }
    final password = await keyManager.obtainKey();

    final handle = await openDatabase(
      path,
      password: password,
      version: Schema.version,
      onConfigure: (db) async {
        // Enforced per-connection, not stored in the file.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        for (var v = 0; v < version; v++) {
          for (final statement in Schema.migrations[v]) {
            batch.execute(statement);
          }
        }
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        final batch = db.batch();
        for (var v = oldVersion; v < newVersion; v++) {
          for (final statement in Schema.migrations[v]) {
            batch.execute(statement);
          }
        }
        await batch.commit(noResult: true);
      },
    );

    _db = handle;
    return handle;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Irreversibly removes the encrypted database file and its key.
  ///
  /// Only for device loss / decommissioning. Anything that reaches here has
  /// already been confirmed by the user at the UI layer.
  Future<void> destroy() async {
    final keyManager = _keyManager;
    if (keyManager == null) {
      throw StateError('A test handle owns no key and no file to destroy.');
    }
    await close();
    final directory = await getApplicationDocumentsDirectory();
    await deleteDatabase(p.join(directory.path, fileName));
    await keyManager.destroyKey();
  }
}
