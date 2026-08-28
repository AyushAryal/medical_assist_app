import '../../core/db/db_types.dart';
import 'sync_entity.dart';

enum MedicationStatus { active, onHold, completed, stopped }

extension MedicationStatusX on MedicationStatus {
  String get label => switch (this) {
        MedicationStatus.active => 'Active',
        MedicationStatus.onHold => 'On hold',
        MedicationStatus.completed => 'Completed',
        MedicationStatus.stopped => 'Stopped',
      };

  static MedicationStatus parse(String? value) =>
      MedicationStatus.values.where((s) => s.name == value).firstOrNull ??
      MedicationStatus.active;
}

/// Common administration routes, abbreviated the way they are written on a
/// prescription.
abstract final class MedicationRoutes {
  static const List<String> common = <String>[
    'PO', 'IV', 'IM', 'SC', 'SL', 'PR', 'PV', 'TOP', 'INH', 'NEB', 'OU', 'NAS',
  ];
}

/// Latin-derived frequency shorthand. Offered as quick chips so the clinician
/// taps rather than types the most common ten.
abstract final class MedicationFrequencies {
  static const List<String> common = <String>[
    'OD', 'BD', 'TDS', 'QDS', 'PRN', 'STAT', 'Nocte', 'Mane', 'Q4H', 'Q6H', 'Q8H',
  ];
}

class Medication extends SyncEntity {
  const Medication({
    required super.id,
    required this.patientId,
    this.encounterId,
    required this.name,
    this.dose,
    this.doseUnit,
    this.route,
    this.frequency,
    this.duration,
    this.indication,
    this.status = MedicationStatus.active,
    this.startedOn,
    this.stoppedOn,
    this.stopReason,
    this.prescriber,
    this.notes,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
    super.revision,
    super.syncStatus,
  });

  final String patientId;
  final String? encounterId;
  final String name;
  final String? dose;
  final String? doseUnit;
  final String? route;
  final String? frequency;
  final String? duration;
  final String? indication;
  final MedicationStatus status;
  final DateTime? startedOn;
  final DateTime? stoppedOn;
  final String? stopReason;
  final String? prescriber;
  final String? notes;

  bool get isActive => status == MedicationStatus.active;

  /// "Amoxicillin 500 mg PO TDS × 5 days" — the single line a clinician scans.
  String get sig => <String?>[
        name,
        [dose, doseUnit].where((s) => s != null && s.isNotEmpty).join(' '),
        route,
        frequency,
        duration == null || duration!.isEmpty ? null : '× $duration',
      ].where((s) => s != null && s.isNotEmpty).join(' ');

  factory Medication.fromMap(Map<String, Object?> map) => Medication(
        id: map['id'] as String,
        patientId: map['patient_id'] as String,
        encounterId: map['encounter_id'] as String?,
        name: map['name'] as String,
        dose: map['dose'] as String?,
        doseUnit: map['dose_unit'] as String?,
        route: map['route'] as String?,
        frequency: map['frequency'] as String?,
        duration: map['duration'] as String?,
        indication: map['indication'] as String?,
        status: MedicationStatusX.parse(map['status'] as String?),
        startedOn: parseIsoDate(map['started_on'] as String?),
        stoppedOn: parseIsoDate(map['stopped_on'] as String?),
        stopReason: map['stop_reason'] as String?,
        prescriber: map['prescriber'] as String?,
        notes: map['notes'] as String?,
        createdAt: fromEpoch(map['created_at'] as int),
        updatedAt: fromEpoch(map['updated_at'] as int),
        deletedAt: fromEpochOrNull(map['deleted_at'] as int?),
        revision: map['revision'] as int? ?? 1,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        ...envelopeMap(),
        'patient_id': patientId,
        'encounter_id': encounterId,
        'name': name,
        'dose': dose,
        'dose_unit': doseUnit,
        'route': route,
        'frequency': frequency,
        'duration': duration,
        'indication': indication,
        'status': status.name,
        'started_on': toIsoDateOrNull(startedOn),
        'stopped_on': toIsoDateOrNull(stoppedOn),
        'stop_reason': stopReason,
        'prescriber': prescriber,
        'notes': notes,
      };
}
