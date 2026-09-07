import '../../core/db/db_types.dart';
import 'encounter.dart';
import 'sync_entity.dart';

/// Where an appointment sits in the front-desk workflow.
///
/// `noShow` is a first-class outcome, not an absence of one. Missed
/// appointments are clinically meaningful — a diabetic patient who misses
/// three reviews is a safety signal, and that only exists if it is recorded.
enum AppointmentStatus {
  scheduled,
  confirmed,
  arrived,
  inProgress,
  completed,
  noShow,
  cancelled,
}

extension AppointmentStatusX on AppointmentStatus {
  String get label => switch (this) {
        AppointmentStatus.scheduled => 'Scheduled',
        AppointmentStatus.confirmed => 'Confirmed',
        AppointmentStatus.arrived => 'Arrived',
        AppointmentStatus.inProgress => 'In progress',
        AppointmentStatus.completed => 'Completed',
        AppointmentStatus.noShow => 'Did not attend',
        AppointmentStatus.cancelled => 'Cancelled',
      };

  /// Still expected to happen — drives the "upcoming" and "waiting" lists.
  bool get isOpen => this == AppointmentStatus.scheduled ||
      this == AppointmentStatus.confirmed ||
      this == AppointmentStatus.arrived ||
      this == AppointmentStatus.inProgress;

  bool get isWaiting => this == AppointmentStatus.arrived;

  bool get isFinished => this == AppointmentStatus.completed ||
      this == AppointmentStatus.noShow ||
      this == AppointmentStatus.cancelled;

  static AppointmentStatus parse(String? value) =>
      AppointmentStatus.values.where((s) => s.name == value).firstOrNull ??
      AppointmentStatus.scheduled;
}

/// A booked slot. Distinct from [Encounter], which records that care actually
/// happened; [encounterId] links the two once the visit starts.
class Appointment extends SyncEntity {
  const Appointment({
    required super.id,
    required this.patientId,
    required this.clinicId,
    this.encounterId,
    required this.scheduledAt,
    this.durationMinutes = 15,
    this.type = EncounterType.followUp,
    this.status = AppointmentStatus.scheduled,
    this.reason,
    this.notes,
    this.providerName,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledReason,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
    super.revision,
    super.syncStatus,
  });

  final String patientId;
  final String clinicId;
  final String? encounterId;
  final DateTime scheduledAt;
  final int durationMinutes;
  final EncounterType type;
  final AppointmentStatus status;
  final String? reason;
  final String? notes;
  final String? providerName;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? cancelledReason;

  DateTime get scheduledEnd =>
      scheduledAt.add(Duration(minutes: durationMinutes));

  bool get isToday {
    final now = DateTime.now();
    return scheduledAt.year == now.year &&
        scheduledAt.month == now.month &&
        scheduledAt.day == now.day;
  }

  /// Past its slot and still not seen. Surfaced so a patient who has been
  /// sitting in the waiting room is not quietly forgotten.
  bool get isOverdue =>
      status.isOpen && DateTime.now().isAfter(scheduledEnd);

  /// How long an arrived patient has been waiting.
  Duration? get waitingFor {
    if (status != AppointmentStatus.arrived || arrivedAt == null) return null;
    return DateTime.now().difference(arrivedAt!);
  }

  factory Appointment.fromMap(Map<String, Object?> map) => Appointment(
        id: map['id'] as String,
        patientId: map['patient_id'] as String,
        clinicId: map['clinic_id'] as String,
        encounterId: map['encounter_id'] as String?,
        scheduledAt: fromEpoch(map['scheduled_at'] as int),
        durationMinutes: map['duration_minutes'] as int? ?? 15,
        type: EncounterTypeX.parse(map['type'] as String?),
        status: AppointmentStatusX.parse(map['status'] as String?),
        reason: map['reason'] as String?,
        notes: map['notes'] as String?,
        providerName: map['provider_name'] as String?,
        arrivedAt: fromEpochOrNull(map['arrived_at'] as int?),
        startedAt: fromEpochOrNull(map['started_at'] as int?),
        completedAt: fromEpochOrNull(map['completed_at'] as int?),
        cancelledReason: map['cancelled_reason'] as String?,
        createdAt: fromEpoch(map['created_at'] as int),
        updatedAt: fromEpoch(map['updated_at'] as int),
        deletedAt: fromEpochOrNull(map['deleted_at'] as int?),
        revision: map['revision'] as int? ?? 1,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        ...envelopeMap(),
        'patient_id': patientId,
        'clinic_id': clinicId,
        'encounter_id': encounterId,
        'scheduled_at': toEpoch(scheduledAt),
        'duration_minutes': durationMinutes,
        'type': type.name,
        'status': status.name,
        'reason': reason,
        'notes': notes,
        'provider_name': providerName,
        'arrived_at': toEpochOrNull(arrivedAt),
        'started_at': toEpochOrNull(startedAt),
        'completed_at': toEpochOrNull(completedAt),
        'cancelled_reason': cancelledReason,
      };

  Appointment copyWith({
    String? encounterId,
    DateTime? scheduledAt,
    int? durationMinutes,
    EncounterType? type,
    AppointmentStatus? status,
    String? reason,
    String? notes,
    String? providerName,
    DateTime? arrivedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    String? cancelledReason,
    DateTime? deletedAt,
  }) =>
      Appointment(
        id: id,
        patientId: patientId,
        clinicId: clinicId,
        encounterId: encounterId ?? this.encounterId,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        type: type ?? this.type,
        status: status ?? this.status,
        reason: reason ?? this.reason,
        notes: notes ?? this.notes,
        providerName: providerName ?? this.providerName,
        arrivedAt: arrivedAt ?? this.arrivedAt,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        cancelledReason: cancelledReason ?? this.cancelledReason,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt ?? this.deletedAt,
        revision: revision + 1,
        syncStatus: SyncStatus.pending,
      );
}
