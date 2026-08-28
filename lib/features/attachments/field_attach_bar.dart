import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design/design.dart';

import '../../data/models/attachment.dart';
import 'voice_note_button.dart';

/// Capture controls that sit on the header of a single note section.
///
/// Camera, gallery, file and dictation are all one tap from the field being
/// written, because the moment to capture a wound photo is while examining the
/// wound — not later, from a separate attachments screen.
class FieldAttachBar extends StatelessWidget {
  const FieldAttachBar({
    super.key,
    required this.enabled,
    required this.onCaptured,
    this.onDictate,
  });

  final bool enabled;

  /// Opens the full dictation flow — record, trim, transcribe, review.
  ///
  /// When null the bar falls back to [VoiceNoteButton], which records straight
  /// to an attachment with no transcript. That path is kept for callers outside
  /// the note editor, where there is no text field for a transcript to go into.
  final VoidCallback? onDictate;

  final Future<void> Function({
    required File file,
    required AttachmentKind kind,
    String? mimeType,
    int? durationMs,
  }) onCaptured;

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(
        source: source,
        // Clinical photographs need detail, but a full-resolution phone image
        // is tens of megabytes on a device holding a whole clinic's records.
        maxWidth: 2400,
        imageQuality: 88,
      );
      if (shot == null) return;
      await onCaptured(
        file: File(shot.path),
        kind: AttachmentKind.photo,
        mimeType: shot.mimeType ?? 'image/jpeg',
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not add image: $error')),
      );
    }
  }

  Future<void> _pickFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf', 'jpg', 'jpeg', 'png', 'txt'],
      );
      final path = picked?.path;
      if (path == null) return;
      await onCaptured(
        file: File(path),
        kind: path.toLowerCase().endsWith('.pdf')
            ? AttachmentKind.document
            : AttachmentKind.photo,
        mimeType: path.toLowerCase().endsWith('.pdf')
            ? 'application/pdf'
            : 'image/jpeg',
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not add file: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final m = context.metrics;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (onDictate case final dictate?)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Dictate into this section',
            icon: const Icon(Icons.mic_none_outlined, size: 20),
            onPressed: dictate,
          )
        else
          VoiceNoteButton(
            onRecorded: (file, duration) => onCaptured(
              file: file,
              kind: AttachmentKind.audio,
              mimeType: 'audio/mp4',
              durationMs: duration.inMilliseconds,
            ),
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Take a photo',
          icon: const Icon(Icons.photo_camera_outlined, size: 20),
          onPressed: () => _pickImage(context, ImageSource.camera),
        ),
        PopupMenuButton<String>(
          tooltip: 'Attach a file',
          icon: const Icon(Icons.attach_file, size: 20),
          padding: EdgeInsets.zero,
          onSelected: (value) => value == 'gallery'
              ? _pickImage(context, ImageSource.gallery)
              : _pickFile(context),
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'gallery',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.photo_library_outlined),
                title: Text('From gallery'),
              ),
            ),
            const PopupMenuItem<String>(
              value: 'file',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.folder_open_outlined),
                title: Text('Document or PDF'),
              ),
            ),
          ],
        ),
        SizedBox(width: m.spaceXs),
      ],
    );
  }
}
