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
/// can *circle* the part that matters — a freeform loop, the way Circle to
/// Search works — and recognition is confined to what they drew around (native
/// Vision reads only that region), leaving the letterhead unread.
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

  /// The circled region (normalised, top-left) OCR is confined to, or null for
  /// the whole page — the bounding box of what the user drew around.
  Rect? _region;

  /// The freeform loop the user drew, kept to draw the "ink" over the page.
  List<Offset>? _ink;

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
      // Fall back to a square box; the loop still maps proportionally.
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

  static Rect? _boundsOf(List<Offset> points) {
    if (points.length < 3) return null;
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final p in points) {
      minX = p.dx < minX ? p.dx : minX;
      minY = p.dy < minY ? p.dy : minY;
      maxX = p.dx > maxX ? p.dx : maxX;
      maxY = p.dy > maxY ? p.dy : maxY;
    }
    if (maxX - minX < 0.04 || maxY - minY < 0.04) return null; // just a tap
    const pad = 0.012;
    return Rect.fromLTRB(
      (minX - pad).clamp(0.0, 1.0),
      (minY - pad).clamp(0.0, 1.0),
      (maxX + pad).clamp(0.0, 1.0),
      (maxY + pad).clamp(0.0, 1.0),
    );
  }

  void _onDraw(List<Offset> points) => setState(() => _ink = points);

  void _onDrawEnd(List<Offset> points) {
    final bounds = _boundsOf(points);
    setState(() {
      _region = bounds;
      _ink = bounds == null ? null : points;
    });
    _run();
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
            _ImageCanvas(
              imagePath: widget.imagePath,
              aspect: _aspect,
              sweep: _sweep,
              scanning: _busy,
              ink: _ink,
              region: _region,
              onDraw: _onDraw,
              onDrawEnd: _onDrawEnd,
            ),
            SizedBox(height: m.spaceSm),
            _RegionControls(
              hasRegion: _region != null,
              onClear: () {
                setState(() {
                  _region = null;
                  _ink = null;
                });
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
                    ? 'Nothing readable inside your circle. Try circling a '
                        'larger area, or a straighter, brighter photo.'
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
        'Tip: circle part of the page to read just that — skip letterheads '
        'and footers.',
        style: context.texts.bodySmall
            ?.copyWith(color: context.palette.onSurfaceMuted),
      );
    }
    return Row(
      children: <Widget>[
        Icon(Icons.gesture, size: 16, color: context.palette.onSurfaceMuted),
        SizedBox(width: context.metrics.spaceXs),
        Expanded(
          child: Text('Reading what you circled.',
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

/// The captured image with a scan line while reading, and a freeform
/// circle-to-select gesture. Points are normalised (0–1) so the loop maps onto
/// the recogniser's region regardless of display size.
class _ImageCanvas extends StatelessWidget {
  const _ImageCanvas({
    required this.imagePath,
    required this.aspect,
    required this.sweep,
    required this.scanning,
    required this.ink,
    required this.region,
    required this.onDraw,
    required this.onDrawEnd,
  });

  final String imagePath;
  final double aspect;
  final Animation<double> sweep;
  final bool scanning;
  final List<Offset>? ink;
  final Rect? region;
  final ValueChanged<List<Offset>> onDraw;
  final ValueChanged<List<Offset>> onDrawEnd;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final box = Size(width, width / (aspect == 0 ? 1 : aspect));
        final points = <Offset>[];

        Offset norm(Offset p) => Offset(
              (p.dx / box.width).clamp(0.0, 1.0),
              (p.dy / box.height).clamp(0.0, 1.0),
            );

        return ClipRRect(
          borderRadius: BorderRadius.circular(m.radiusLg),
          child: GestureDetector(
            onPanStart: (d) {
              points
                ..clear()
                ..add(norm(d.localPosition));
              onDraw(List<Offset>.of(points));
            },
            onPanUpdate: (d) {
              points.add(norm(d.localPosition));
              onDraw(List<Offset>.of(points));
            },
            onPanEnd: (_) => onDrawEnd(List<Offset>.of(points)),
            child: SizedBox(
              width: box.width,
              height: box.height,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: Image.file(File(imagePath), fit: BoxFit.fill),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _LassoPainter(
                        ink: ink,
                        region: region,
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

class _LassoPainter extends CustomPainter {
  _LassoPainter({
    required this.ink,
    required this.region,
    required this.scrim,
    required this.stroke,
  });

  final List<Offset>? ink;
  final Rect? region;
  final Color scrim;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // Dim everything outside the circled region.
    if (region != null) {
      final r = Rect.fromLTRB(
        region!.left * size.width,
        region!.top * size.height,
        region!.right * size.width,
        region!.bottom * size.height,
      );
      final outside = Path()
        ..addRect(Offset.zero & size)
        ..addRRect(RRect.fromRectXY(r, 8, 8))
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(outside, Paint()..color = scrim);
    }

    // The freeform "ink" the user drew.
    final pts = ink;
    if (pts != null && pts.length > 1) {
      final path = Path()
        ..moveTo(pts.first.dx * size.width, pts.first.dy * size.height);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      // Glow, then a crisp line on top.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 12
          ..color = stroke.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 4
          ..color = stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_LassoPainter old) =>
      old.ink != ink ||
      old.region != region ||
      old.scrim != scrim ||
      old.stroke != stroke;
}
