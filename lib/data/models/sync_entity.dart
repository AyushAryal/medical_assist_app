import '../../core/db/db_types.dart';

/// The record envelope every syncable model carries.
///
/// Each aggregate row has the same six housekeeping columns — a UUID id, the
/// created/updated instants, a soft-delete tombstone, a revision counter and a
/// sync status. They were declared, parsed and serialised identically in every
/// model; this is that shape written once.
///
/// Models `extend SyncEntity` and forward these through `super.` constructor
/// parameters, so a model body declares only its own fields. `toMap()` spreads
/// [envelopeMap] and adds the rest; `fromMap` still reads the six columns
/// explicitly, because Dart has no way to splat named arguments.
abstract class SyncEntity {
  const SyncEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final String syncStatus;

  /// The six envelope columns, for spreading into a subclass `toMap()`:
  /// `<String, Object?>{ ...envelopeMap(), 'substance': substance, ... }`.
  Map<String, Object?> envelopeMap() => <String, Object?>{
        'id': id,
        'created_at': toEpoch(createdAt),
        'updated_at': toEpoch(updatedAt),
        'deleted_at': toEpochOrNull(deletedAt),
        'revision': revision,
        'sync_status': syncStatus,
      };
}
