import '../../core/db/db_types.dart';

enum EncounterType {
  newPatient,
  followUp,
  emergency,
  procedure,
  telehealth,
  homeVisit,
  antenatal,
  immunisation,
}

extension EncounterTypeX on EncounterType {
  String get label => switch (this) {
        EncounterType.newPatient => 'New patient',
        EncounterType.followUp => 'Follow-up',
        EncounterType.emergency => 'Emergency',
        EncounterType.procedure => 'Procedure',
        EncounterType.telehealth => 'Telehealth',
        EncounterType.homeVisit => 'Home visit',
        EncounterType.antenatal => 'Antenatal',
        EncounterType.immunisation => 'Immunisation',
      };

  static EncounterType parse(String? value) =>
      EncounterType.values.where((t) => t.name == value).firstOrNull ??
      EncounterType.followUp;
}

/// `signed` is terminal for editing. An error found afterwards produces an
/// amendment, never an edit — that is what makes the record defensible.
enum EncounterStatus { draft, inProgress, completed, signed, amended, cancelled }

extension EncounterStatusX on EncounterStatus {
  String get label => switch (this) {
        EncounterStatus.draft => 'Draft',
        EncounterStatus.inProgress => 'In progress',
        EncounterStatus.completed => 'Completed',
        EncounterStatus.signed => 'Signed',
        EncounterStatus.amended => 'Amended',
        EncounterStatus.cancelled => 'Cancelled',
      };

  bool get isOpen =>
      this == EncounterStatus.draft || this == EncounterStatus.inProgress;

  bool get isLocked =>
      this == EncounterStatus.signed || this == EncounterStatus.amended;

  static EncounterStatus parse(String? value) =>
      EncounterStatus.values.where((s) => s.name == value).firstOrNull ??
      EncounterStatus.draft;
}

enum Disposition {
  home,
  referred,
  admitted,
  observation,
  transferred,
  leftWithoutBeingSeen,
  deceased,
}

extension DispositionX on Disposition {
  String get label => switch (this) {
        Disposition.home => 'Discharged home',
        Disposition.referred => 'Referred',
        Disposition.admitted => 'Admitted',
        Disposition.observation => 'Observation',
        Disposition.transferred => 'Transferred',
        Disposition.leftWithoutBeingSeen => 'Left without being seen',
        Disposition.deceased => 'Deceased',
      };

  static Disposition? parse(String? value) =>
      Disposition.values.where((d) => d.name == value).firstOrNull;
}

/// One episode of care: a visit, a call, a home review.
class Encounter {
  const Encounter({
    required this.id,
    required this.patientId,
    required this.clinicId,
    this.type = EncounterType.followUp,
    this.status = EncounterStatus.draft,
    this.chiefComplaint,
    required this.startedAt,
    this.endedAt,
    this.disposition,
    this.followUpDate,
    this.referredTo,
    this.providerName,
    this.providerId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String patientId;
  final String clinicId;
  final EncounterType type;
  final EncounterStatus status;

  /// The patient's own words. Kept verbatim and separate from the assessment.
  final String? chiefComplaint;
  final DateTime startedAt;
  final DateTime? endedAt;
  final Disposition? disposition;
  final DateTime? followUpDate;
  final String? referredTo;
  final String? providerName;
  final String? providerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final String syncStatus;

  Duration? get duration => endedAt?.difference(startedAt);

  bool get isOpen => status.isOpen;
  bool get isLocked => status.isLocked;

  factory Encounter.fromMap(Map<String, Object?> map) => Encounter(
        id: map['id'] as String,
        patientId: map['patient_id'] as String,
        clinicId: map['clinic_id'] as String,
        type: EncounterTypeX.parse(map['type'] as String?),
        status: EncounterStatusX.parse(map['status'] as String?),
        chiefComplaint: map['chief_complaint'] as String?,
        startedAt: fromEpoch(map['started_at'] as int),
        endedAt: fromEpochOrNull(map['ended_at'] as int?),
        disposition: DispositionX.parse(map['disposition'] as String?),
        followUpDate: parseIsoDate(map['follow_up_date'] as String?),
        referredTo: map['referred_to'] as String?,
        providerName: map['provider_name'] as String?,
        providerId: map['provider_id'] as String?,
        createdAt: fromEpoch(map['created_at'] as int),
        updatedAt: fromEpoch(map['updated_at'] as int),
        deletedAt: fromEpochOrNull(map['deleted_at'] as int?),
        revision: map['revision'] as int? ?? 1,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'patient_id': patientId,
        'clinic_id': clinicId,
        'type': type.name,
        'status': status.name,
        'chief_complaint': chiefComplaint,
        'started_at': toEpoch(startedAt),
        'ended_at': toEpochOrNull(endedAt),
        'disposition': disposition?.name,
        'follow_up_date': toIsoDateOrNull(followUpDate),
        'referred_to': referredTo,
        'provider_name': providerName,
        'provider_id': providerId,
        'created_at': toEpoch(createdAt),
        'updated_at': toEpoch(updatedAt),
        'deleted_at': toEpochOrNull(deletedAt),
        'revision': revision,
        'sync_status': syncStatus,
      };

  Encounter copyWith({
    EncounterType? type,
    EncounterStatus? status,
    String? chiefComplaint,
    DateTime? endedAt,
    Disposition? disposition,
    DateTime? followUpDate,
    String? referredTo,
    String? providerName,
    DateTime? deletedAt,
  }) =>
      Encounter(
        id: id,
        patientId: patientId,
        clinicId: clinicId,
        type: type ?? this.type,
        status: status ?? this.status,
        chiefComplaint: chiefComplaint ?? this.chiefComplaint,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        disposition: disposition ?? this.disposition,
        followUpDate: followUpDate ?? this.followUpDate,
        referredTo: referredTo ?? this.referredTo,
        providerName: providerName ?? this.providerName,
        providerId: providerId,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt ?? this.deletedAt,
        revision: revision + 1,
        syncStatus: SyncStatus.pending,
      );
}
