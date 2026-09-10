import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/design/design.dart';
import '../../../core/routing/fade_through_route.dart';

/// Full-screen preview of a rendered letter, with print and share built in.
///
/// Share is also how the letter is emailed: the share sheet offers Mail (and
/// anything else installed) with the PDF already attached — no copy of the
/// letter is written to disk by this screen itself.
class LetterPreviewScreen extends StatelessWidget {
  const LetterPreviewScreen({
    super.key,
    required this.title,
    required this.render,
  });

  final String title;

  /// Renders the current text — called again on print/share so the preview
  /// can never drift from what is sent.
  final Future<Uint8List> Function() render;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required Future<Uint8List> Function() build,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      FadeThroughRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LetterPreviewScreen(title: title, render: build),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeName = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.surfaceSunken,
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: (_) => render(),
        pdfFileName: '$safeName.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        // The default preview paints its own grey behind the page and a
        // stark actions bar; sit it on the app's own surfaces instead.
        scrollViewDecoration: BoxDecoration(color: palette.surfaceSunken),
        actionBarTheme: PdfActionBarTheme(
          backgroundColor: palette.surface,
          iconColor: palette.onSurface,
        ),
        previewPageMargin: EdgeInsets.symmetric(
          horizontal: context.metrics.spaceLg,
          vertical: context.metrics.spaceMd,
        ),
        loadingWidget: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
