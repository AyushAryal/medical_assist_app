import '../../core/db/db_types.dart';

enum AttachmentKind { photo, document, audio, video }

extension AttachmentKindX on AttachmentKind {
  String get label => switch (this) {
        AttachmentKind.photo => 'Photo',
        AttachmentKind.document => 'Document',
        AttachmentKind.audio => 'Voice note',
        AttachmentKind.video => 'Video',
      };

  static AttachmentKind parse(String? value) =>
      AttachmentKind.values.where((k) => k.name == value).firstOrNull ??
      AttachmentKind.document;
}

/// What the attachment hangs off. Kept polymorphic so a wound photo can belong
/// to an encounter while an ID scan belongs to the patient record itself.
enum AttachmentOwner { patient, encounter, note, vitals }

extension AttachmentOwnerX on AttachmentOwner {
  static AttachmentOwner parse(String? value) =>
      AttachmentOwner.values.where((o) => o.name == value).firstOrNull ??
      AttachmentOwner.patient;
}

/// Metadata for a file held inside the app's private storage.
///
/// [relativePath] is relative to the app documents directory — absolute paths
/// break on iOS, where the container UUID changes between installs and OS
/// upgrades.
class Attachment {
  const Attachment({
    required this.id,
    required this.patientId,
    required this.ownerType,
    this.ownerId,
    required this.kind,
    required this.fileName,
    required this.relativePath,
    this.mimeType,
    this.sizeBytes,
    this.sha256,
    this.durationMs,
    this.bodySite,
    this.caption,
    this.capturedAt,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String patientId;
  final AttachmentOwner ownerType;
  final String? ownerId;
  final AttachmentKind kind;
  final String fileName;
  final String relativePath;
  final String? mimeType;
  final int? sizeBytes;

  /// Content digest, so a corrupted or swapped file is detectable.
  final String? sha256;
  final int? durationMs;

  /// For clinical photos: where on the body. Without it a wound photo taken
  /// three weeks apart cannot be reliably compared.
  final String? bodySite;
  final String? caption;
  final DateTime? capturedAt;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final String syncStatus;

  String get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get durationLabel {
    final ms = durationMs;
    if (ms == null) return '';
    final total = Duration(milliseconds: ms);
    final minutes = total.inMinutes;
    final seconds = total.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  factory Attachment.fromMap(Map<String, Object?> map) => Attachment(
        id: map['id'] as String,
        patientId: map['patient_id'] as String,
        ownerType: AttachmentOwnerX.parse(map['owner_type'] as String?),
        ownerId: map['owner_id'] as String?,
        kind: AttachmentKindX.parse(map['kind'] as String?),
        fileName: map['file_name'] as String,
        relativePath: map['relative_path'] as String,
        mimeType: map['mime_type'] as String?,
        sizeBytes: map['size_bytes'] as int?,
        sha256: map['sha256'] as String?,
        durationMs: map['duration_ms'] as int?,
        bodySite: map['body_site'] as String?,
        caption: map['caption'] as String?,
        capturedAt: fromEpochOrNull(map['captured_at'] as int?),
        createdBy: map['created_by'] as String?,
        createdAt: fromEpoch(map['created_at'] as int),
        updatedAt: fromEpoch(map['updated_at'] as int),
        deletedAt: fromEpochOrNull(map['deleted_at'] as int?),
        revision: map['revision'] as int? ?? 1,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'patient_id': patientId,
        'owner_type': ownerType.name,
        'owner_id': ownerId,
        'kind': kind.name,
        'file_name': fileName,
        'relative_path': relativePath,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'sha256': sha256,
        'duration_ms': durationMs,
        'body_site': bodySite,
        'caption': caption,
        'captured_at': toEpochOrNull(capturedAt),
        'created_by': createdBy,
        'created_at': toEpoch(createdAt),
        'updated_at': toEpoch(updatedAt),
        'deleted_at': toEpochOrNull(deletedAt),
        'revision': revision,
        'sync_status': syncStatus,
      };
}
