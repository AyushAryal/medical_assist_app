import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/ids.dart';
import '../dao/attachment_dao.dart';
import '../models/attachment.dart';

/// Owns attachment bytes on disk and keeps them in step with the metadata rows.
///
/// Files live under the app's private documents directory, partitioned by
/// patient. That directory is excluded from OS-level cloud backup by the
/// platform configuration, so clinical photos never leak into a personal
/// iCloud or Google account.
///
/// Note the asymmetry with the database: SQLCipher encrypts the record, but
/// attachment *bytes* are protected only by the OS sandbox and full-disk
/// encryption in round 1. Per-file encryption using the same keystore-held key
/// is tracked in `SystemArchitecture.md` § Attachment encryption.
class AttachmentService {
  AttachmentService(this._dao);

  final AttachmentDao _dao;

  static const String _rootFolder = 'attachments';

  Future<Directory> _patientDirectory(String patientId) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, _rootFolder, patientId));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<String> absolutePath(Attachment attachment) async {
    final documents = await getApplicationDocumentsDirectory();
    return p.join(documents.path, attachment.relativePath);
  }

  /// Copies [source] into private storage and records it.
  ///
  /// The source is copied rather than moved: `image_picker` and `file_picker`
  /// hand back paths in shared caches that the OS may reclaim at any moment.
  Future<Attachment> store({
    required File source,
    required String patientId,
    required AttachmentOwner ownerType,
    String? ownerId,
    required AttachmentKind kind,
    String? mimeType,
    String? caption,
    String? bodySite,
    int? durationMs,
    String? createdBy,
  }) async {
    final directory = await _patientDirectory(patientId);
    final id = newId();
    final extension = p.extension(source.path);
    final fileName = '$id$extension';
    final destination = File(p.join(directory.path, fileName));

    await source.copy(destination.path);

    final bytes = await destination.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    final now = DateTime.now();

    final attachment = Attachment(
      id: id,
      patientId: patientId,
      ownerType: ownerType,
      ownerId: ownerId,
      kind: kind,
      fileName: p.basename(source.path),
      relativePath: p.join(_rootFolder, patientId, fileName),
      mimeType: mimeType,
      sizeBytes: bytes.length,
      sha256: digest,
      durationMs: durationMs,
      bodySite: bodySite,
      caption: caption,
      capturedAt: now,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );

    return _dao.insert(attachment);
  }

  /// Confirms the bytes on disk still match the digest recorded at capture.
  Future<bool> verify(Attachment attachment) async {
    final path = await absolutePath(attachment);
    final file = File(path);
    if (!await file.exists()) return false;
    if (attachment.sha256 == null) return true;
    final digest = sha256.convert(await file.readAsBytes()).toString();
    return digest == attachment.sha256;
  }

  /// Archives the row first, then unlinks. If the unlink fails the record is
  /// already hidden, and the orphaned file is swept up by [reclaimOrphans].
  Future<void> remove(Attachment attachment) async {
    await _dao.archive(attachment.id);
    final file = File(await absolutePath(attachment));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Deletes files under the attachment root that no live row references.
  Future<int> reclaimOrphans(String patientId) async {
    final rows = await _dao.forPatient(patientId);
    final known = rows.map((a) => p.basename(a.relativePath)).toSet();
    final directory = await _patientDirectory(patientId);

    var removed = 0;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      if (known.contains(p.basename(entity.path))) continue;
      await entity.delete();
      removed++;
    }
    return removed;
  }
}
