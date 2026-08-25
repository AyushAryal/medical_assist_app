import '../../core/db/db_types.dart';

/// The set of actions worth recording. Reads are included deliberately:
/// "who looked at this chart" is the question an access investigation starts
/// with.
enum AuditAction {
  appUnlock,
  appUnlockFailed,
  appLock,
  patientView,
  patientCreate,
  patientUpdate,
  patientDelete,
  appointmentBook,
  appointmentUpdate,
  encounterCreate,
  encounterUpdate,
  encounterSign,
  vitalsCreate,
  vitalsUpdate,
  noteCreate,
  noteUpdate,
  noteSign,
  noteAmend,
  attachmentAdd,
  attachmentDelete,
  export,
  databaseDestroy,
}

extension AuditActionX on AuditAction {
  String get label => switch (this) {
        AuditAction.appUnlock => 'App unlocked',
        AuditAction.appUnlockFailed => 'Failed unlock attempt',
        AuditAction.appLock => 'App locked',
        AuditAction.patientView => 'Viewed patient',
        AuditAction.patientCreate => 'Created patient',
        AuditAction.patientUpdate => 'Updated patient',
        AuditAction.patientDelete => 'Removed patient',
        AuditAction.appointmentBook => 'Booked appointment',
        AuditAction.appointmentUpdate => 'Updated appointment',
        AuditAction.encounterCreate => 'Started encounter',
        AuditAction.encounterUpdate => 'Updated encounter',
        AuditAction.encounterSign => 'Signed encounter',
        AuditAction.vitalsCreate => 'Recorded vitals',
        AuditAction.vitalsUpdate => 'Updated vitals',
        AuditAction.noteCreate => 'Created note',
        AuditAction.noteUpdate => 'Edited note',
        AuditAction.noteSign => 'Signed note',
        AuditAction.noteAmend => 'Amended note',
        AuditAction.attachmentAdd => 'Added attachment',
        AuditAction.attachmentDelete => 'Removed attachment',
        AuditAction.export => 'Exported data',
        AuditAction.databaseDestroy => 'Destroyed local database',
      };

  static AuditAction? parse(String? value) =>
      AuditAction.values.where((a) => a.name == value).firstOrNull;
}

/// An append-only audit entry.
///
/// [detail] must never carry clinical content — it holds field names and
/// counts, not values. An audit log that quotes the record it is protecting
/// just doubles the amount of PHI at risk.
class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.occurredAt,
    required this.action,
    this.actor,
    this.entityType,
    this.entityId,
    this.patientId,
    this.detail,
    this.deviceId,
    this.synced = false,
  });

  final String id;
  final DateTime occurredAt;
  final AuditAction action;
  final String? actor;
  final String? entityType;
  final String? entityId;
  final String? patientId;
  final String? detail;
  final String? deviceId;
  final bool synced;

  factory AuditEvent.fromMap(Map<String, Object?> map) => AuditEvent(
        id: map['id'] as String,
        occurredAt: fromEpoch(map['occurred_at'] as int),
        action: AuditActionX.parse(map['action'] as String?) ??
            AuditAction.patientView,
        actor: map['actor'] as String?,
        entityType: map['entity_type'] as String?,
        entityId: map['entity_id'] as String?,
        patientId: map['patient_id'] as String?,
        detail: map['detail'] as String?,
        deviceId: map['device_id'] as String?,
        synced: intToBool(map['synced']),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'occurred_at': toEpoch(occurredAt),
        'action': action.name,
        'actor': actor,
        'entity_type': entityType,
        'entity_id': entityId,
        'patient_id': patientId,
        'detail': detail,
        'device_id': deviceId,
        'synced': boolToInt(synced),
      };
}
