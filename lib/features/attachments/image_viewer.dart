import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/design/design.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/attachment.dart';

/// Full-screen, pinch-zoomable image viewer.
///
/// Rendered in-app rather than handed to the platform gallery on purpose:
/// passing a clinical photograph to an external viewer copies PHI out of this
/// app's sandbox, where its retention and backup are no longer controlled.
class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.images,
    required this.paths,
    this.initialIndex = 0,
  });

  final List<Attachment> images;

  /// Absolute path per attachment, resolved by the caller.
  final Map<String, String> paths;
  final int initialIndex;

  static Future<void> show(
    BuildContext context, {
    required List<Attachment> images,
    required Map<String, String> paths,
    int initialIndex = 0,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ImageViewer(
          images: images,
          paths: paths,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final current = widget.images[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          current.caption ?? current.bodySite ?? 'Clinical image',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: <Widget>[
          if (widget.images.length > 1)
            Center(
              child: Padding(
                padding: EdgeInsets.only(right: m.spaceLg),
                child: Text(
                  '${_index + 1} / ${widget.images.length}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: widget.images.length,
              itemBuilder: (context, index) {
                final attachment = widget.images[index];
                final path = widget.paths[attachment.id];
                if (path == null) {
                  return const Center(
                    child: Text(
                      'Image unavailable',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text(
                          'Image could not be decoded',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.black,
            padding: EdgeInsets.fromLTRB(
              m.spaceLg,
              m.spaceSm,
              m.spaceLg,
              m.spaceLg,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (current.bodySite != null)
                    Text(
                      'Site: ${current.bodySite}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  Text(
                    '${Fmt.dateTime(current.capturedAt ?? current.createdAt)}'
                    '${current.createdBy == null ? '' : ' · ${current.createdBy}'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
