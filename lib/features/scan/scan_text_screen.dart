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

  /// True while a finger is down drawing — freezes the scroll view so the loop
  /// is captured instead of scrolling the page.
  bool _drawing = false;

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
      final result = await _scanner.scan(widget.imagePath, lasso: _ink);
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

  void _onDrawStart() => setState(() => _drawing = true);

  void _onDrawEnd(List<Offset> points) {
    final bounds = _boundsOf(points);
    setState(() {
      _drawing = false;
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
          // Frozen while drawing so the loop is captured, not scrolled.
          physics: _drawing ? const NeverScrollableScrollPhysics() : null,
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
              onDrawStart: _onDrawStart,
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
                subtitle: result.markdown.contains('|')
                    ? 'Table layout detected'
                    : null,
                child: MarkdownView(data: result.markdown),
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
                            Navigator.of(context).pop<String>(result.markdown),
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
class _ImageCanvas extends StatefulWidget {
  const _ImageCanvas({
    required this.imagePath,
    required this.aspect,
    required this.sweep,
    required this.scanning,
    required this.ink,
    required this.region,
    required this.onDrawStart,
    required this.onDrawEnd,
  });

  final String imagePath;
  final double aspect;
  final Animation<double> sweep;
  final bool scanning;
  final List<Offset>? ink;
  final Rect? region;
  final VoidCallback onDrawStart;
  final ValueChanged<List<Offset>> onDrawEnd;

  @override
  State<_ImageCanvas> createState() => _ImageCanvasState();
}

class _ImageCanvasState extends State<_ImageCanvas> {
  // Persists across rebuilds — a local list would reset on every setState mid
  // draw and the stroke would never accumulate.
  final List<Offset> _points = <Offset>[];
  Size _box = Size.zero;

  Offset _norm(Offset p) => Offset(
        (_box.width == 0 ? 0.0 : p.dx / _box.width).clamp(0.0, 1.0),
        (_box.height == 0 ? 0.0 : p.dy / _box.height).clamp(0.0, 1.0),
      );

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _box = Size(width, width / (widget.aspect == 0 ? 1 : widget.aspect));
        final display = _points.isNotEmpty ? _points : widget.ink;

        return ClipRRect(
          borderRadius: BorderRadius.circular(m.radiusLg),
          // Listener, not GestureDetector: raw pointer events are captured even
          // though this sits inside a scroll view (the list is frozen while
          // drawing), so a vertical loop is drawn rather than scrolling away.
          child: Listener(
            onPointerDown: (e) {
              setState(() {
                _points
                  ..clear()
                  ..add(_norm(e.localPosition));
              });
              widget.onDrawStart();
            },
            onPointerMove: (e) =>
                setState(() => _points.add(_norm(e.localPosition))),
            onPointerUp: (_) {
              widget.onDrawEnd(List<Offset>.of(_points));
              setState(_points.clear);
            },
            onPointerCancel: (_) {
              widget.onDrawEnd(List<Offset>.of(_points));
              setState(_points.clear);
            },
            child: SizedBox(
              width: _box.width,
              height: _box.height,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: Image.file(File(widget.imagePath), fit: BoxFit.fill),
                  ),
                  // Dim outside the circled region (plain scrim, no gradient).
                  if (widget.region != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _DimPainter(
                          region: widget.region!,
                          scrim: palette.scrim.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  // The glowing, gradient-animated loop (design layer).
                  if (display != null && display.length > 1)
                    Positioned.fill(child: GlowLasso(points: display)),
                  if (widget.scanning)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: widget.sweep,
                        builder: (context, _) {
                          final t =
                              Curves.easeInOut.transform(widget.sweep.value);
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

/// Dims the page outside the circled region. The glowing loop itself is drawn
/// by [GlowLasso] from the design layer (that is where gradients live).
class _DimPainter extends CustomPainter {
  _DimPainter({required this.region, required this.scrim});

  final Rect region;
  final Color scrim;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      region.left * size.width,
      region.top * size.height,
      region.right * size.width,
      region.bottom * size.height,
    );
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectXY(r, 8, 8))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = scrim);
  }

  @override
  bool shouldRepaint(_DimPainter old) =>
      old.region != region || old.scrim != scrim;
}
