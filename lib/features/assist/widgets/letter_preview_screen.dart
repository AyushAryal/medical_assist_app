import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/design/design.dart';
import '../../../core/routing/fade_through_route.dart';

/// Full-screen preview of a rendered letter, pinch-zoomable, with print and
/// share.
///
/// Not `PdfPreview`: its page list owns every gesture, so pinch never reaches
/// a zoom — the one thing a person checking a letter's small print needs.
/// The PDF is rastered once and each page sits in its own [InteractiveViewer].
///
/// Share is also how the letter is emailed: the share sheet offers Mail (and
/// anything else installed) with the PDF already attached.
class LetterPreviewScreen extends StatefulWidget {
  const LetterPreviewScreen({
    super.key,
    required this.title,
    required this.render,
  });

  final String title;

  /// Renders the current text — the same bytes back the preview, the printer
  /// and the share sheet, so what is seen is what is sent.
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
  State<LetterPreviewScreen> createState() => _LetterPreviewScreenState();
}

class _LetterPreviewScreenState extends State<LetterPreviewScreen> {
  Uint8List? _bytes;
  List<Uint8List>? _pages;
  Object? _error;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.render();
      // 160 dpi: crisp enough to zoom into, small enough to raster instantly.
      final pages = <Uint8List>[
        await for (final page in Printing.raster(bytes, dpi: 160))
          await page.toPng(),
      ];
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _pages = pages;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  String get _fileName {
    final safe = widget.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '$safe.pdf';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final pages = _pages;

    return Scaffold(
      backgroundColor: palette.surfaceSunken,
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          if (pages != null && pages.length > 1)
            Center(
              child: Padding(
                padding: EdgeInsets.only(right: m.spaceLg),
                child: Text(
                  '${_page + 1} of ${pages.length}',
                  style: context.texts.labelMedium
                      ?.copyWith(color: palette.onSurfaceMuted),
                ),
              ),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(m.spaceXl),
                child: Text(
                  'Could not render the letter: $_error',
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium,
                ),
              ),
            )
          : pages == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: <Widget>[
                    Expanded(
                      child: PageView.builder(
                        itemCount: pages.length,
                        onPageChanged: (page) =>
                            setState(() => _page = page),
                        itemBuilder: (context, index) => InteractiveViewer(
                          maxScale: 5,
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(m.spaceLg),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: palette.shadow
                                          .withValues(alpha: 0.35),
                                      blurRadius: m.shadowBlur,
                                      offset: Offset(0, m.shadowOffsetY),
                                    ),
                                  ],
                                ),
                                child: Image.memory(
                                  pages[index],
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // The two actions the preview exists for, always visible.
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          m.spaceLg,
                          m.spaceSm,
                          m.spaceLg,
                          m.spaceMd,
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () => Printing.layoutPdf(
                                  name: _fileName,
                                  onLayout: (_) async => _bytes!,
                                ),
                                icon: const Icon(Icons.print_outlined,
                                    size: 18),
                                label: const Text('Print'),
                              ),
                            ),
                            SizedBox(width: m.spaceSm),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () => Printing.sharePdf(
                                  bytes: _bytes!,
                                  filename: _fileName,
                                ),
                                icon: const Icon(Icons.ios_share, size: 18),
                                label: const Text('Share'),
                              ),
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
