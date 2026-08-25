import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/db/db_types.dart';

enum NoteType { soap, progress, procedure, referral, discharge, telephone }

extension NoteTypeX on NoteType {
  String get label => switch (this) {
        NoteType.soap => 'SOAP note',
        NoteType.progress => 'Progress note',
        NoteType.procedure => 'Procedure note',
        NoteType.referral => 'Referral letter',
        NoteType.discharge => 'Discharge summary',
        NoteType.telephone => 'Telephone encounter',
      };

  static NoteType parse(String? value) =>
      NoteType.values.where((t) => t.name == value).firstOrNull ?? NoteType.soap;
}

enum NoteStatus { draft, signed, amended }

extension NoteStatusX on NoteStatus {
  String get label => switch (this) {
        NoteStatus.draft => 'Draft',
        NoteStatus.signed => 'Signed',
        NoteStatus.amended => 'Amended',
      };

  /// Signing freezes the note. Everything after that is an appended amendment.
  bool get isLocked => this != NoteStatus.draft;

  static NoteStatus parse(String? value) =>
      NoteStatus.values.where((s) => s.name == value).firstOrNull ??
      NoteStatus.draft;
}

/// A SOAP-structured clinical note.
///
/// The four sections are stored separately rather than as one blob because
/// they are read separately: on a follow-up the clinician jumps straight to
/// the previous Assessment and Plan.
class ClinicalNote {
  const ClinicalNote({
    required this.id,
    required this.patientId,
    required this.encounterId,
    this.noteType = NoteType.soap,
    this.templateId,
    this.subjective,
    this.objective,
    this.assessment,
    this.plan,
    this.workingNotes,
    this.status = NoteStatus.draft,
    this.signedAt,
    this.signedBy,
    this.contentHash,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String patientId;
  final String encounterId;
  final NoteType noteType;
  final String? templateId;

  /// What the patient reports: history, symptoms, review of systems.
  final String? subjective;

  /// What the clinician finds: examination, vitals, results.
  final String? objective;

  /// The clinician's interpretation and differential.
  final String? assessment;

  /// What happens next: investigations, treatment, follow-up, safety-netting.
  final String? plan;

  /// Raw, unsorted material — a whole consultation dictated in one go, before
  /// any of it has been placed.
  ///
  /// Not part of [canonicalContent], so it is not covered by the signature: it
  /// is scratch, not record. The editor clears it when the note is signed and
  /// warns first if anything is left in it, which is what stops dictation
  /// that nobody sorted from quietly never reaching the chart.
  final String? workingNotes;

  final NoteStatus status;
  final DateTime? signedAt;
  final String? signedBy;

  /// SHA-256 over the signed content. Any later divergence between the stored
  /// text and this hash is detectable tampering.
  final String? contentHash;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final String syncStatus;

  bool get isLocked => status.isLocked;

  bool get isEmpty =>
      (subjective ?? '').trim().isEmpty &&
      (objective ?? '').trim().isEmpty &&
      (assessment ?? '').trim().isEmpty &&
      (plan ?? '').trim().isEmpty;

  int get filledSectionCount => <String?>[subjective, objective, assessment, plan]
      .where((s) => (s ?? '').trim().isNotEmpty)
      .length;

  /// Canonical serialisation used for the signature hash. Field order and
  /// separators are fixed so the same content always hashes identically.
  String canonicalContent() => jsonEncode(<String, Object?>{
        'id': id,
        'encounterId': encounterId,
        'patientId': patientId,
        'noteType': noteType.name,
        'subjective': subjective ?? '',
        'objective': objective ?? '',
        'assessment': assessment ?? '',
        'plan': plan ?? '',
      });

  String computeHash() =>
      sha256.convert(utf8.encode(canonicalContent())).toString();

  /// True when the stored text still matches the hash captured at signing.
  bool verifyIntegrity() =>
      contentHash == null ? true : contentHash == computeHash();

  factory ClinicalNote.fromMap(Map<String, Object?> map) => ClinicalNote(
        id: map['id'] as String,
        patientId: map['patient_id'] as String,
        encounterId: map['encounter_id'] as String,
        noteType: NoteTypeX.parse(map['note_type'] as String?),
        templateId: map['template_id'] as String?,
        subjective: map['subjective'] as String?,
        objective: map['objective'] as String?,
        assessment: map['assessment'] as String?,
        plan: map['plan'] as String?,
        status: NoteStatusX.parse(map['status'] as String?),
        signedAt: fromEpochOrNull(map['signed_at'] as int?),
        signedBy: map['signed_by'] as String?,
        workingNotes: map['working_notes'] as String?,
        contentHash: map['content_hash'] as String?,
        createdAt: fromEpoch(map['created_at'] as int),
        updatedAt: fromEpoch(map['updated_at'] as int),
        deletedAt: fromEpochOrNull(map['deleted_at'] as int?),
        revision: map['revision'] as int? ?? 1,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'patient_id': patientId,
        'encounter_id': encounterId,
        'note_type': noteType.name,
        'template_id': templateId,
        'subjective': subjective,
        'objective': objective,
        'assessment': assessment,
        'plan': plan,
        'status': status.name,
        'signed_at': toEpochOrNull(signedAt),
        'signed_by': signedBy,
        'working_notes': workingNotes,
        'content_hash': contentHash,
        'created_at': toEpoch(createdAt),
        'updated_at': toEpoch(updatedAt),
        'deleted_at': toEpochOrNull(deletedAt),
        'revision': revision,
        'sync_status': syncStatus,
      };

  ClinicalNote copyWith({
    NoteType? noteType,
    String? templateId,
    String? subjective,
    String? objective,
    String? assessment,
    String? plan,
    NoteStatus? status,
    DateTime? signedAt,
    String? signedBy,
    String? workingNotes,
    /// Signing empties the scratch, and `workingNotes ?? this.workingNotes`
    /// can never express that.
    bool clearWorkingNotes = false,
    String? contentHash,
  }) =>
      ClinicalNote(
        id: id,
        patientId: patientId,
        encounterId: encounterId,
        noteType: noteType ?? this.noteType,
        templateId: templateId ?? this.templateId,
        subjective: subjective ?? this.subjective,
        objective: objective ?? this.objective,
        assessment: assessment ?? this.assessment,
        plan: plan ?? this.plan,
        status: status ?? this.status,
        signedAt: signedAt ?? this.signedAt,
        signedBy: signedBy ?? this.signedBy,
        workingNotes:
            clearWorkingNotes ? null : (workingNotes ?? this.workingNotes),
        contentHash: contentHash ?? this.contentHash,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt,
        revision: revision + 1,
        syncStatus: SyncStatus.pending,
      );
}

/// An append-only correction to a signed note.
///
/// Amendments chain by hash: each carries the hash of the entry before it, so
/// removing one from the middle of the chain is detectable.
class NoteAmendment {
  const NoteAmendment({
    required this.id,
    required this.noteId,
    required this.body,
    required this.reason,
    this.author,
    this.previousHash,
    this.contentHash,
    required this.createdAt,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String noteId;
  final String body;

  /// Required. A correction without a stated reason is not auditable.
  final String reason;
  final String? author;
  final String? previousHash;
  final String? contentHash;
  final DateTime createdAt;
  final String syncStatus;

  factory NoteAmendment.fromMap(Map<String, Object?> map) => NoteAmendment(
        id: map['id'] as String,
        noteId: map['note_id'] as String,
        body: map['body'] as String,
        reason: map['reason'] as String,
        author: map['author'] as String?,
        previousHash: map['previous_hash'] as String?,
        contentHash: map['content_hash'] as String?,
        createdAt: fromEpoch(map['created_at'] as int),
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'note_id': noteId,
        'body': body,
        'reason': reason,
        'author': author,
        'previous_hash': previousHash,
        'content_hash': contentHash,
        'created_at': toEpoch(createdAt),
        'sync_status': syncStatus,
      };
}
