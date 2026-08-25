import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/design/design.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/attachment.dart';
import 'image_viewer.dart';
import 'inline_audio_player.dart';

/// Renders a field's attachments inline, immediately below that field.
///
/// Voice notes get a working player, images get tappable thumbnails, and
/// documents get a labelled card. Nothing here requires navigating to a
/// separate attachments screen — the evidence stays next to the text it
/// belongs to.
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({
    super.key,
    required this.attachments,
    required this.paths,
    this.onDelete,
    this.onOpenDocument,
    this.onTranscribe,
    this.transcribingId,
  });

  final List<Attachment> attachments;

  /// Absolute path per attachment id, resolved by the caller (paths are
  /// stored relative, because the iOS container id changes between installs).
  final Map<String, String> paths;

  final void Function(Attachment)? onDelete;
  final void Function(Attachment)? onOpenDocument;

  /// Turns an existing recording into text.
  ///
  /// Needed because dictation captured before a speech model was installed —
  /// or before this feature existed — would otherwise be audio forever, with
  /// no way to get at what was said other than listening to all of it.
  final void Function(Attachment)? onTranscribe;

  /// The recording currently being transcribed, if any.
  final String? transcribingId;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    final m = context.metrics;
    final audio = attachments
        .where((a) => a.kind == AttachmentKind.audio)
        .toList(growable: false);
    final images = attachments
        .where((a) => a.kind == AttachmentKind.photo)
        .toList(growable: false);
    final documents = attachments
        .where((a) =>
            a.kind == AttachmentKind.document || a.kind == AttachmentKind.video)
        .toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(top: m.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final recording in audio)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceSm),
              child: paths[recording.id] == null
                  ? const SizedBox.shrink()
                  : AiGlowBorder(
                      active: transcribingId == recording.id,
                      borderRadius:
                          BorderRadius.circular(context.metrics.radiusMd),
                      child: InlineAudioPlayer(
                        filePath: paths[recording.id]!,
                        label: recording.caption ??
                            'Voice note · '
                                '${Fmt.time(recording.capturedAt ?? recording.createdAt)}',
                        durationMs: recording.durationMs,
                        onDelete: onDelete == null
                            ? null
                            : () => onDelete!(recording),
                        onTranscribe: onTranscribe == null
                            ? null
                            : () => onTranscribe!(recording),
                        isTranscribing: transcribingId == recording.id,
                      ),
                    ),
            ),

          if (images.isNotEmpty)
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, _) => SizedBox(width: m.spaceSm),
                itemBuilder: (context, index) => _Thumbnail(
                  attachment: images[index],
                  path: paths[images[index].id],
                  onTap: () => ImageViewer.show(
                    context,
                    images: images,
                    paths: paths,
                    initialIndex: index,
                  ),
                  onDelete: onDelete,
                ),
              ),
            ),

          for (final document in documents)
            Padding(
              padding: EdgeInsets.only(top: m.spaceSm),
              child: _DocumentCard(
                attachment: document,
                onTap: onOpenDocument == null
                    ? null
                    : () => onOpenDocument!(document),
                onDelete: onDelete,
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.attachment,
    required this.path,
    required this.onTap,
    this.onDelete,
  });

  final Attachment attachment;
  final String? path;
  final VoidCallback onTap;
  final void Function(Attachment)? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return SizedBox(
      width: 84,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(m.radiusSm),
              child: Material(
                color: palette.surfaceSunken,
                child: InkWell(
                  onTap: onTap,
                  child: path == null
                      ? Icon(Icons.broken_image_outlined,
                          color: palette.onSurfaceMuted)
                      : Image.file(
                          File(path!),
                          fit: BoxFit.cover,
                          cacheWidth: 240,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.broken_image_outlined,
                            color: palette.onSurfaceMuted,
                          ),
                        ),
                ),
              ),
            ),
          ),
          if (attachment.bodySite != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: Colors.black.withValues(alpha: 0.55),
                child: Text(
                  attachment.bodySite!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          if (onDelete != null)
            Positioned(
              top: -6,
              right: -6,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'Remove image',
                // Deliberately not an avatar: avatars in this app mean "a
                // person", and their colour is derived from a record id.
                icon: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, size: 12, color: palette.critical),
                ),
                onPressed: () => onDelete!(attachment),
              ),
            ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.attachment,
    required this.onTap,
    this.onDelete,
  });

  final Attachment attachment;
  final VoidCallback? onTap;
  final void Function(Attachment)? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final isPdf = (attachment.mimeType ?? '').contains('pdf') ||
        attachment.fileName.toLowerCase().endsWith('.pdf');

    return Material(
      color: palette.surfaceMuted,
      borderRadius: BorderRadius.circular(m.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(m.spaceMd),
          child: Row(
            children: <Widget>[
              Icon(
                isPdf
                    ? Icons.picture_as_pdf_outlined
                    : attachment.kind == AttachmentKind.video
                        ? Icons.videocam_outlined
                        : Icons.description_outlined,
                color: palette.accent,
              ),
              SizedBox(width: m.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      attachment.caption ?? attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelMedium,
                    ),
                    Text(
                      <String>[
                        Fmt.dateShort(
                          attachment.capturedAt ?? attachment.createdAt,
                        ),
                        if (attachment.sizeLabel.isNotEmpty)
                          attachment.sizeLabel,
                      ].join(' · '),
                      style: context.texts.labelSmall,
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: 'Remove document',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete!(attachment),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
