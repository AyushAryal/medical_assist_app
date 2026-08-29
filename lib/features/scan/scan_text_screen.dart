import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../data/services/ocr/text_scanner.dart';

/// Reads text off a captured image and hands it back.
///
/// The recognised text is *extracted*, not authored — the screen shows exactly
/// what was on the page and lets the clinician use it or not. It never files
/// anything itself; it returns the text to whoever opened it.
///
/// Real pages are rarely clean: letterheads, footers, stamps. So the clinician
/// can drag a box over just the part that matters, and recognition is confined
/// to it (native Vision reads only that region) — the letterhead is simply not
/// read rather than read and discarded.
class ScanTextScreen extends StatefulWidget {
  const ScanTextScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<ScanTextScreen> createState() => _ScanTextScreenState();
}

class _ScanTextScreenState extends State<ScanTextScreen>
    with SingleTickerProviderStateMixin {
  final TextScanner _scanner = TextScanner.platformDefault();
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  double _aspect = 1;
  ScannedText? _result;
  bool _busy = true;
  Object? _error;

  /// The committed region (normalised, top-left), or null for the whole page.
  Rect? _region;

  /// The rectangle being dragged right now (normalised), before release.
  Rect? _dragging;

  @override
  void initState() {
    super.initState();
    _loadAspect();
    _run();
  }

  Future<void> _loadAspect() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() => _aspect = frame.image.width / frame.image.height);
      }
    } on Object {
      // Fall back to a square box; selection still works proportionally.
    }
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!_sweep.isAnimating) _sweep.repeat();
    try {
      final result = await _scanner.scan(widget.imagePath, region: _region);
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _sweep.stop();
      }
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final result = _result;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Scan text')),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              m.spaceLg, m.spaceLg, m.spaceLg, m.spaceLg * 3),
          children: <Widget>[
            _ImageWithRegion(
              imagePath: widget.imagePath,
              aspect: _aspect,
              sweep: _sweep,
              scanning: _busy,
              region: _dragging ?? _region,
              onRegionChanged: (r) => setState(() => _dragging = r),
              onRegionCommitted: (r) {
                setState(() {
                  _dragging = null;
                  _region = r;
                });
                _run();
              },
            ),
            SizedBox(height: m.spaceSm),
            _RegionControls(
              hasRegion: _region != null,
              onClear: () {
                setState(() => _region = null);
                _run();
              },
            ),
            SizedBox(height: m.spaceMd),
            if (_busy)
              Row(
                children: <Widget>[
                  const AiSparkleIcon(size: 18),
                  SizedBox(width: m.spaceSm),
                  Text('Reading text…', style: context.texts.bodyMedium),
                ],
              )
            else if (_error != null)
              Text('Could not read this image. Try a clearer, well-lit photo.',
                  style: context.texts.bodySmall)
            else if (result == null || result.isEmpty)
              EmptyState(
                icon: Icons.document_scanner_outlined,
                title: 'No text found',
                message: _region != null
                    ? 'Nothing readable in that box. Try a larger area or a '
                        'straighter, brighter photo.'
                    : 'Try a straighter, brighter photo of the page.',
              )
            else
              SectionCard(
                title: 'Found ${result.blockCount} '
                    '${result.blockCount == 1 ? 'block' : 'blocks'} of text',
                child: SelectableText(
                  result.text,
                  style: context.texts.bodyMedium,
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: (result != null && !result.isEmpty)
          ? SafeArea(
              child: Padding(
                padding: EdgeInsets.all(m.spaceLg),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _run,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Rescan'),
                      ),
                    ),
                    SizedBox(width: m.spaceMd),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop<String>(result.text),
                        icon: const Icon(Icons.check),
                        label: const Text('Use text'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _RegionControls extends StatelessWidget {
  const _RegionControls({required this.hasRegion, required this.onClear});

  final bool hasRegion;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (!hasRegion) {
      return Text(
        'Tip: drag a box on the image to read just that part — skip '
        'letterheads and footers.',
        style: context.texts.bodySmall
            ?.copyWith(color: context.palette.onSurfaceMuted),
      );
    }
    return Row(
      children: <Widget>[
        Icon(Icons.crop_free,
            size: 16, color: context.palette.onSurfaceMuted),
        SizedBox(width: context.metrics.spaceXs),
        Expanded(
          child: Text('Reading the selected region only.',
              style: context.texts.bodySmall),
        ),
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Whole page'),
        ),
      ],
    );
  }
}

/// The captured image with a scan line while reading, and a drag-to-select
/// region overlay. Coordinates are normalised (0–1) so they map straight onto
/// the recogniser's region of interest regardless of display size.
class _ImageWithRegion extends StatelessWidget {
  const _ImageWithRegion({
    required this.imagePath,
    required this.aspect,
    required this.sweep,
    required this.scanning,
    required this.region,
    required this.onRegionChanged,
    required this.onRegionCommitted,
  });

  final String imagePath;
  final double aspect;
  final Animation<double> sweep;
  final bool scanning;
  final Rect? region;
  final ValueChanged<Rect> onRegionChanged;
  final ValueChanged<Rect?> onRegionCommitted;

  Rect _rectFrom(Offset a, Offset b, Size box) {
    Offset n(Offset p) => Offset(
          (p.dx / box.width).clamp(0.0, 1.0),
          (p.dy / box.height).clamp(0.0, 1.0),
        );
    return Rect.fromPoints(n(a), n(b));
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final box = Size(width, width / (aspect == 0 ? 1 : aspect));
        Offset? start;

        return ClipRRect(
          borderRadius: BorderRadius.circular(m.radiusLg),
          child: GestureDetector(
            onPanStart: (d) => start = d.localPosition,
            onPanUpdate: (d) {
              if (start == null) return;
              onRegionChanged(_rectFrom(start!, d.localPosition, box));
            },
            onPanEnd: (_) {
              final r = region;
              start = null;
              // Ignore an accidental tap; keep only a real box.
              if (r == null || r.width < 0.03 || r.height < 0.03) {
                onRegionCommitted(null);
              } else {
                onRegionCommitted(r);
              }
            },
            child: SizedBox(
              width: box.width,
              height: box.height,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: Image.file(File(imagePath), fit: BoxFit.fill),
                  ),
                  if (region != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RegionPainter(
                          region: region!,
                          scrim: palette.scrim.withValues(alpha: 0.45),
                          stroke: palette.accent,
                        ),
                      ),
                    ),
                  if (scanning)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: sweep,
                        builder: (context, _) {
                          final t = Curves.easeInOut.transform(sweep.value);
                          return Align(
                            alignment: Alignment(0, -1 + 2 * t),
                            child: Container(
                              height: 2.5,
                              decoration: BoxDecoration(
                                color: palette.accent,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: palette.accent.withValues(alpha: 0.7),
                                    blurRadius: 16,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RegionPainter extends CustomPainter {
  _RegionPainter({
    required this.region,
    required this.scrim,
    required this.stroke,
  });

  final Rect region;
  final Color scrim;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      region.left * size.width,
      region.top * size.height,
      region.width * size.width,
      region.height * size.height,
    );
    // Dim everything except the selection.
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = scrim);
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = stroke,
    );
  }

  @override
  bool shouldRepaint(_RegionPainter old) =>
      old.region != region || old.scrim != scrim || old.stroke != stroke;
}
