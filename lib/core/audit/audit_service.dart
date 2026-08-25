import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../data/models/audit_event.dart';
import '../db/app_database.dart';
import '../db/db_types.dart';
import '../utils/ids.dart';

/// Append-only PHI access log.
///
/// Two rules hold everywhere this is called from:
///
/// 1. `detail` carries field *names*, never field *values*. The audit trail
///    must not become a second copy of the record.
/// 2. Logging never blocks or fails a clinical action. A dropped audit row is
///    a problem; a clinician unable to record vitals because logging failed is
///    a bigger one.
class AuditService {
  AuditService(this._database);

  final AppDatabase _database;
  String? _actor;
  String? _deviceId;

  static const String table = 'audit_events';

  void configure({String? actor, String? deviceId}) {
    _actor = actor;
    _deviceId = deviceId;
  }

  Future<void> log(
    AuditAction action, {
    String? entityType,
    String? entityId,
    String? patientId,
    String? detail,
  }) async {
    if (!_database.isOpen) return;
    final event = AuditEvent(
      id: newId(),
      occurredAt: DateTime.now(),
      action: action,
      actor: _actor,
      entityType: entityType,
      entityId: entityId,
      patientId: patientId,
      detail: detail,
      deviceId: _deviceId,
    );
    try {
      await _database.db.insert(
        table,
        event.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException {
      // Intentionally swallowed — see rule 2 above.
    }
  }

  Future<List<AuditEvent>> recent({int limit = 200}) async {
    final rows = await _database.db.query(
      table,
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(AuditEvent.fromMap).toList();
  }

  Future<List<AuditEvent>> forPatient(String patientId, {int limit = 100}) async {
    final rows = await _database.db.query(
      table,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(AuditEvent.fromMap).toList();
  }

  /// Rows older than [retention] are purged. Retention is a policy decision —
  /// many jurisdictions require years — so the caller supplies it rather than
  /// this class assuming one.
  Future<int> purgeOlderThan(Duration retention) async {
    final cutoff = toEpoch(DateTime.now().subtract(retention));
    return _database.db.delete(
      table,
      where: 'occurred_at < ? AND synced = 1',
      whereArgs: [cutoff],
    );
  }
}
