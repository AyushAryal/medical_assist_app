import '../../core/db/db_types.dart';
import 'sync_entity.dart';

enum ProblemStatus { active, resolved, inactive }

extension ProblemStatusX on ProblemStatus {
  String get label => switch (this) {
        ProblemStatus.active => 'Active',
        ProblemStatus.resolved => 'Resolved',
        ProblemStatus.inactive => 'Inactive',
      };

  static ProblemStatus parse(String? value) =>
      ProblemStatus.values.where((s) => s.name == value).firstOrNull ??
      ProblemStatus.active;
}

/// An entry on the patient's problem list — the running summary a clinician
/// reads first to understand who they are about to see.
class Problem extends SyncEntity {
  const Problem({
    required super.id,
    required this.patientId,
    required this.display,
    this.codeSystem,
    this.code,
    this.status = ProblemStatus.active,
    this.isChronic = false,
    this.onsetDate,
    this.resolvedDate,
    this.notes,
    this.recordedBy,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
    super.revision,
    super.syncStatus,
  });

  final String patientId;
  final String display;

  /// e.g. `ICD-10`, `SNOMED-CT`. Free-text `display` is always authoritative
  /// for the clinician; the code exists for reporting and future interop.
  final String? codeSystem;
  final String? code;
  final ProblemStatus status;
  final bool isChronic;
  final DateTime? onsetDate;
  final DateTime? resolvedDate;
  final String? notes;
  final String? recordedBy;

  bool get isActive => status == ProblemStatus.active;

  String get codeLabel =>
      (code == null || code!.isEmpty) ? '' : '${codeSystem ?? ''} $code'.trim();

  factory Problem.fromMap(Map<String, Object?> map) => Problem(
        id: map['id'] as String,
        patientId: map['patient_id'] as String,
        display: map['display'] as String,
        codeSystem: map['code_system'] as String?,
        code: map['code'] as String?,
        status: ProblemStatusX.parse(map['status'] as String?),
        isChronic: intToBool(map['is_chronic']),
        onsetDate: parseIsoDate(map['onset_date'] as String?),
        resolvedDate: parseIsoDate(map['resolved_date'] as String?),
        notes: map['notes'] as String?,
        recordedBy: map['recorded_by'] as String?,
        createdAt: fromEpoch(map['created_at'] as int),
        updatedAt: fromEpoch(map['updated_at'] as int),
        deletedAt: fromEpochOrNull(map['deleted_at'] as int?),
        revision: map['revision'] as int? ?? 1,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        ...envelopeMap(),
        'patient_id': patientId,
        'display': display,
        'code_system': codeSystem,
        'code': code,
        'status': status.name,
        'is_chronic': boolToInt(isChronic),
        'onset_date': toIsoDateOrNull(onsetDate),
        'resolved_date': toIsoDateOrNull(resolvedDate),
        'notes': notes,
        'recorded_by': recordedBy,
      };
}
