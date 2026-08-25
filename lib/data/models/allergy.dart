import '../../core/db/db_types.dart';

enum AllergySeverity { unknown, mild, moderate, severe, anaphylaxis }

extension AllergySeverityX on AllergySeverity {
  String get label => switch (this) {
        AllergySeverity.unknown => 'Unknown severity',
        AllergySeverity.mild => 'Mild',
        AllergySeverity.moderate => 'Moderate',
        AllergySeverity.severe => 'Severe',
        AllergySeverity.anaphylaxis => 'Anaphylaxis',
      };

  /// Drives the red banner. Severe and anaphylactic reactions are the ones a
  /// prescriber must see before writing anything.
  bool get isHighRisk =>
      this == AllergySeverity.severe || this == AllergySeverity.anaphylaxis;

  static AllergySeverity parse(String? value) =>
      AllergySeverity.values.where((s) => s.name == value).firstOrNull ??
      AllergySeverity.unknown;
}

enum AllergyCategory { drug, food, environmental, biologic, other }

extension AllergyCategoryX on AllergyCategory {
  String get label => switch (this) {
        AllergyCategory.drug => 'Drug',
        AllergyCategory.food => 'Food',
        AllergyCategory.environmental => 'Environmental',
        AllergyCategory.biologic => 'Biologic',
        AllergyCategory.other => 'Other',
      };

  static AllergyCategory parse(String? value) =>
      AllergyCategory.values.where((c) => c.name == value).firstOrNull ??
      AllergyCategory.drug;
}

/// `refuted` exists because allergies are frequently mis-reported; marking one
/// refuted preserves the history while removing it from the active banner.
enum AllergyRecordStatus { active, inactive, refuted }

extension AllergyRecordStatusX on AllergyRecordStatus {
  String get label => switch (this) {
        AllergyRecordStatus.active => 'Active',
        AllergyRecordStatus.inactive => 'Inactive',
        AllergyRecordStatus.refuted => 'Refuted',
      };

  static AllergyRecordStatus parse(String? value) =>
      AllergyRecordStatus.values.where((s) => s.name == value).firstOrNull ??
      AllergyRecordStatus.active;
}

class Allergy {
  const Allergy({
    required this.id,
    required this.patientId,
    required this.substance,
    this.category = AllergyCategory.drug,
    this.reaction,
    this.severity = AllergySeverity.unknown,
    this.status = AllergyRecordStatus.active,
    this.onsetDate,
    this.notes,
    this.recordedBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String patientId;
  final String substance;
  final AllergyCategory category;
  final String? reaction;
  final AllergySeverity severity;
  final AllergyRecordStatus status;
  final DateTime? onsetDate;
  final String? notes;
  final String? recordedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final String syncStatus;

  bool get isActive => status == AllergyRecordStatus.active;

  String get summary =>
      reaction?.isNotEmpty == true ? '$substance — $reaction' : substance;

  factory Allergy.fromMap(Map<String, Object?> map) => Allergy(
        id: map['id'] as String,
        patientId: map['patient_id'] as String,
        substance: map['substance'] as String,
        category: AllergyCategoryX.parse(map['category'] as String?),
        reaction: map['reaction'] as String?,
        severity: AllergySeverityX.parse(map['severity'] as String?),
        status: AllergyRecordStatusX.parse(map['status'] as String?),
        onsetDate: parseIsoDate(map['onset_date'] as String?),
        notes: map['notes'] as String?,
        recordedBy: map['recorded_by'] as String?,
        createdAt: fromEpoch(map['created_at'] as int),
        updatedAt: fromEpoch(map['updated_at'] as int),
        deletedAt: fromEpochOrNull(map['deleted_at'] as int?),
        revision: map['revision'] as int? ?? 1,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'patient_id': patientId,
        'substance': substance,
        'category': category.name,
        'reaction': reaction,
        'severity': severity.name,
        'status': status.name,
        'onset_date': toIsoDateOrNull(onsetDate),
        'notes': notes,
        'recorded_by': recordedBy,
        'created_at': toEpoch(createdAt),
        'updated_at': toEpoch(updatedAt),
        'deleted_at': toEpochOrNull(deletedAt),
        'revision': revision,
        'sync_status': syncStatus,
      };
}
