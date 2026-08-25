import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ai/analytics/analysis.dart';
import '../theme/theme_config.dart';
import '../utils/formatters.dart';
import '../theme/theme_scope.dart';

/// Every chart this app draws, behind one widget.
///
/// One widget rather than eight because the *choice* of chart is made upstream
/// from the shape of the data — see `AnalysisSpec.styleFor` — and a caller that
/// had to pick a widget would be making that decision twice, in a place with
/// less information. Here the style arrives with the data.
///
/// Drawn by hand rather than pulled from a charting package. Three reasons,
/// in order of how much they matter: an offline clinical app should not take a
/// dependency it cannot audit for where it sends telemetry; the app's own
/// palette, radii and type scale are the whole visual language and charting
/// libraries bring their own; and every one of these has a caveat to honour —
/// a gap that must stay a gap, a folded "Other" slice, a part-finished final
/// bar — which a general-purpose library has no way to express.
///
/// Motion is deliberate but bounded: the series draws itself in once, over
/// [_drawDuration], and then stops. A chart that pulses forever competes with
/// the data on it.
class DataChart extends StatefulWidget {
  const DataChart({
    super.key,
    required this.style,
    required this.points,
    this.height,
    this.unit,
    this.compact = false,
    this.onTapPoint,
  });

  final ChartStyle style;
  final List<ChartPoint> points;
  final double? height;
  final String? unit;

  /// Tighter type and fewer labels for the floating panel. The data is
  /// identical — a compact chart is the same chart, not a lesser one.
  final bool compact;

  final ValueChanged<ChartPoint>? onTapPoint;

  /// The icon that stands for a chart shape.
  ///
  /// Lives here rather than at each call site because it was already written
  /// twice — in the answer renderer and in the capability sheet — and they had
  /// begun to disagree about which icon a histogram gets.
  static IconData iconFor(ChartStyle style) => switch (style) {
        ChartStyle.pie || ChartStyle.donut => Icons.pie_chart_outline,
        ChartStyle.line || ChartStyle.area => Icons.show_chart,
        ChartStyle.scatter => Icons.scatter_plot_outlined,
        ChartStyle.histogram => Icons.equalizer_outlined,
        ChartStyle.bar || ChartStyle.column => Icons.bar_chart_outlined,
      };

  @override
  State<DataChart> createState() => _DataChartState();
}

class _DataChartState extends State<DataChart>
    with SingleTickerProviderStateMixin {
  static const Duration _drawDuration = Duration(milliseconds: 720);

  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: _drawDuration,
  )..forward();

  int? _touched;

  @override
  void didUpdateWidget(DataChart old) {
    super.didUpdateWidget(old);
    // A new series redraws itself. Without this, tapping a follow-up swaps the
    // numbers under a finished animation and the chart appears to teleport.
    if (old.points != widget.points || old.style != widget.style) {
      _draw
        ..reset()
        ..forward();
      _touched = null;
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  double get _height =>
      widget.height ?? (widget.compact ? 132 : 196);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    if (widget.points.isEmpty) {
      return SizedBox(
        height: _height,
        child: Center(
          child: Text('Nothing to plot', style: context.texts.labelSmall),
        ),
      );
    }

    final series = _Series(
      points: widget.points,
      tones: _tones(palette),
      grid: palette.outline.withValues(alpha: 0.30),
      label: context.texts.labelSmall?.copyWith(fontSize: widget.compact ? 9 : 10),
      onSurface: palette.onSurfaceMuted,
      unit: widget.unit,
      radius: m.radiusSm,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: _height,
          child: GestureDetector(
            onTapDown: (details) => _handleTap(details.localPosition),
            child: AnimatedBuilder(
              animation: _draw,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: _ChartPainter(
                  style: widget.style,
                  series: series,
                  // Eased here rather than on the controller so every painter
                  // shares one curve and the styles come in at the same rate.
                  progress: Curves.easeOutCubic.transform(_draw.value),
                  touched: _touched,
                  textDirection: Directionality.of(context),
                ),
              ),
            ),
          ),
        ),
        if (_touched != null) ...<Widget>[
          SizedBox(height: m.spaceXs),
          _readout(context, widget.points[_touched!]),
        ] else if (widget.style.isShare && !widget.compact) ...<Widget>[
          SizedBox(height: m.spaceSm),
          _legend(context, series),
        ],
      ],
    );
  }

  /// What was tapped, in words.
  ///
  /// A chart is a shape; the moment someone wants a number from it they want
  /// the exact number, and hovering is not available on a device held in one
  /// hand. Tapping states the value and how many rows produced it — the second
  /// being what separates a real difference from three cases.
  Widget _readout(BuildContext context, ChartPoint point) {
    final palette = context.palette;
    final m = context.metrics;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: m.spaceSm,
        vertical: m.spaceXs,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              point.label.isEmpty ? 'Point' : point.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelSmall,
            ),
          ),
          Text(
            _format(point.value, widget.unit),
            style: context.texts.labelMedium?.copyWith(
              color: palette.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (point.n > 0) ...<Widget>[
            SizedBox(width: m.spaceSm),
            Text(
              'n=${point.n}',
              style: context.texts.labelSmall?.copyWith(
                color: palette.onSurfaceMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, _Series series) {
    final m = context.metrics;
    return Wrap(
      spacing: m.spaceMd,
      runSpacing: m.spaceXs,
      children: <Widget>[
        for (var i = 0; i < widget.points.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: series.toneAt(i),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: m.spaceXs),
              Text(
                widget.points[i].label,
                style: context.texts.labelSmall,
              ),
            ],
          ),
      ],
    );
  }

  void _handleTap(Offset position) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    final index = switch (widget.style) {
      ChartStyle.pie || ChartStyle.donut || ChartStyle.scatter => null,
      _ => (position.dx / (width / widget.points.length))
          .floor()
          .clamp(0, widget.points.length - 1),
    };
    setState(() => _touched = _touched == index ? null : index);
    if (index != null && widget.onTapPoint != null) {
      widget.onTapPoint!(widget.points[index]);
    }
  }

  /// The chart palette.
  ///
  /// Built from the accent and the avatar tones — never from the clinical
  /// severity colours. Red in this app means a patient is unwell; a red slice
  /// meaning "appointments in Ward 3" would make that vocabulary unreliable
  /// everywhere it actually matters.
  List<Color> _tones(ClinicalPalette palette) => <Color>[
        palette.primary,
        palette.accent,
        ...palette.avatarTones,
      ];

  static String _format(double value, String? unit) =>
      Fmt.stat(value, unit: unit, missing: 'no data');
}

/// Everything a painter needs that is not geometry.
class _Series {
  _Series({
    required this.points,
    required this.tones,
    required this.grid,
    required this.label,
    required this.onSurface,
    required this.radius,
    this.unit,
  });

  final List<ChartPoint> points;
  final List<Color> tones;
  final Color grid;
  final TextStyle? label;
  final Color onSurface;
  final double radius;
  final String? unit;

  Color toneAt(int index) => tones[index % tones.length];

  Iterable<double> get finite =>
      points.map((p) => p.value).where((v) => !v.isNaN);

  double get maxValue {
    final values = finite;
    if (values.isEmpty) return 1;
    final max = values.reduce(math.max);
    return max <= 0 ? 1 : max;
  }

  double get minValue {
    final values = finite;
    if (values.isEmpty) return 0;
    return values.reduce(math.min);
  }

  double get total => finite.fold<double>(0, (a, b) => a + b);
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.style,
    required this.series,
    required this.progress,
    required this.textDirection,
    this.touched,
  });

  final ChartStyle style;
  final _Series series;
  final double progress;
  final int? touched;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case ChartStyle.pie:
      case ChartStyle.donut:
        _paintRadial(canvas, size, donut: style == ChartStyle.donut);
      case ChartStyle.line:
      case ChartStyle.area:
        _paintLine(canvas, size, filled: style == ChartStyle.area);
      case ChartStyle.scatter:
        _paintScatter(canvas, size);
      case ChartStyle.bar:
      case ChartStyle.column:
      case ChartStyle.histogram:
        _paintBars(canvas, size);
    }
  }

  /// Reserved along the bottom for category labels.
  static const double _axisHeight = 18;

  void _paintBars(Canvas canvas, Size size) {
    final plot = Size(size.width, size.height - _axisHeight);
    final count = series.points.length;
    final slot = plot.width / count;
    // Histograms are a continuous distribution: touching bars say the bins are
    // adjacent ranges, and a gapped one implies categories that are not.
    final gap = style == ChartStyle.histogram
        ? math.min(1.0, slot * 0.04)
        : math.min(10.0, slot * 0.28);
    final max = series.maxValue;

    for (var i = 0; i < count; i++) {
      final point = series.points[i];
      final x = i * slot;
      final track = Rect.fromLTWH(x + gap / 2, 0, slot - gap, plot.height);

      // A faint track marks the slot without competing with the data. It has
      // to stay far lighter than any real bar: a solid track makes an empty
      // week read as a full one, which is worse than drawing nothing.
      canvas.drawRRect(
        RRect.fromRectAndRadius(track, Radius.circular(series.radius)),
        Paint()..color = series.grid.withValues(alpha: 0.35),
      );

      if (point.value.isNaN) continue;
      final fraction = (point.value / max).clamp(0.0, 1.0) * progress;
      final height =
          math.max<double>(fraction * plot.height, point.value > 0 ? 2 : 0);
      if (height <= 0) continue;

      final bar = Rect.fromLTWH(
        x + gap / 2,
        plot.height - height,
        slot - gap,
        height,
      );
      final tone = style == ChartStyle.histogram
          ? series.toneAt(0)
          : series.toneAt(i);
      final highlighted = touched == i;

      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, Radius.circular(series.radius)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[
              tone.withValues(alpha: highlighted ? 1 : 0.85),
              tone.withValues(alpha: highlighted ? 0.85 : 0.55),
            ],
          ).createShader(bar),
      );
    }

    _paintCategoryLabels(canvas, size, slot);
  }

  void _paintCategoryLabels(Canvas canvas, Size size, double slot) {
    final count = series.points.length;
    // Draw every label only while they fit. Past that, thin them evenly rather
    // than letting them overlap into an unreadable smear.
    final step = math.max(1, (count / math.max(1, size.width ~/ 46)).ceil());

    for (var i = 0; i < count; i++) {
      if (i % step != 0 && touched != i) continue;
      final text = series.points[i].label;
      if (text.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: series.label?.copyWith(
            color: touched == i ? series.toneAt(i) : series.onSurface,
            fontWeight: touched == i ? FontWeight.w700 : null,
          ),
        ),
        textDirection: textDirection,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: slot * step);
      painter.paint(
        canvas,
        Offset(
          i * slot + (slot - painter.width) / 2,
          size.height - _axisHeight + 4,
        ),
      );
    }
  }

  void _paintLine(Canvas canvas, Size size, {required bool filled}) {
    final plot = Size(size.width, size.height - _axisHeight);
    final count = series.points.length;
    if (count < 2) return _paintBars(canvas, size);

    final max = series.maxValue;
    // Lines do not have to start at zero, but they must not exaggerate: a
    // floor pinned to the lowest value turns a 2% wobble into a cliff. Anchor
    // at zero for counts, and pad an interval otherwise.
    final min = style == ChartStyle.area
        ? 0.0
        : math.min(0.0, series.minValue);
    final span = (max - min) == 0 ? 1 : max - min;
    final slot = plot.width / (count - 1);

    Offset at(int i) => Offset(
          i * slot,
          plot.height - ((series.points[i].value - min) / span) * plot.height,
        );

    // A gap is a gap. Missing buckets break the path rather than being joined
    // over, because a straight line across a month with no data claims a
    // steady rate through it.
    final runs = <List<Offset>>[];
    var run = <Offset>[];
    for (var i = 0; i < count; i++) {
      if (series.points[i].value.isNaN) {
        if (run.length > 1) runs.add(run);
        run = <Offset>[];
        continue;
      }
      run.add(at(i));
    }
    if (run.length > 1) runs.add(run);

    final tone = series.toneAt(0);
    final reveal = plot.width * progress;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, reveal, size.height));

    for (final points in runs) {
      final path = _smooth(points);

      if (filled) {
        final area = Path.from(path)
          ..lineTo(points.last.dx, plot.height)
          ..lineTo(points.first.dx, plot.height)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                tone.withValues(alpha: 0.34),
                tone.withValues(alpha: 0.02),
              ],
            ).createShader(Rect.fromLTWH(0, 0, plot.width, plot.height)),
        );
      }

      // A soft pass under the stroke. It reads as the line glowing rather than
      // as a second line, which is what keeps this looking generated without
      // making the value harder to read.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = tone.withValues(alpha: 0.16)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = LinearGradient(
            colors: <Color>[tone, series.toneAt(1)],
          ).createShader(Rect.fromLTWH(0, 0, plot.width, plot.height)),
      );

      for (final point in points) {
        canvas.drawCircle(point, 2.6, Paint()..color = tone);
      }
    }
    canvas.restore();

    if (touched != null && !series.points[touched!].value.isNaN) {
      final marker = at(touched!);
      canvas.drawLine(
        Offset(marker.dx, 0),
        Offset(marker.dx, plot.height),
        Paint()
          ..color = tone.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(marker, 5, Paint()..color = tone);
    }

    _paintCategoryLabels(canvas, size, plot.width / count);
  }

  /// A Catmull-Rom-ish curve through the points.
  ///
  /// Curved rather than straight because these are trends, not exact
  /// intermediate values — but the control points are kept short so the curve
  /// never overshoots above the highest point or below the lowest. A smoothed
  /// line that bulges past its own data is a chart that lies for looks.
  Path _smooth(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final dx = (next.dx - current.dx) * 0.38;
      path.cubicTo(
        current.dx + dx,
        current.dy,
        next.dx - dx,
        next.dy,
        next.dx,
        next.dy,
      );
    }
    return path;
  }

  void _paintRadial(Canvas canvas, Size size, {required bool donut}) {
    final total = series.total;
    if (total <= 0) return;

    final radius = math.min(size.width, size.height) / 2 - 6;
    final centre = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: centre, radius: radius);
    // Starts at twelve o'clock and runs clockwise, which is how everyone reads
    // a share, rather than at three o'clock where the maths starts.
    var start = -math.pi / 2;

    for (var i = 0; i < series.points.length; i++) {
      final value = series.points[i].value;
      if (value.isNaN || value <= 0) continue;
      final sweep = (value / total) * 2 * math.pi * progress;
      final tone = series.toneAt(i);
      final pulled = touched == i;
      final offset = pulled
          ? Offset(
              math.cos(start + sweep / 2) * 6,
              math.sin(start + sweep / 2) * 6,
            )
          : Offset.zero;

      canvas.drawArc(
        rect.shift(offset),
        start,
        // A hairline between slices, so two similar tones stay distinguishable
        // without needing a stroke the width of a value.
        math.max(sweep - 0.012, 0.001),
        !donut,
        Paint()
          ..style = donut ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = radius * 0.42
          ..shader = SweepGradient(
            startAngle: start,
            endAngle: start + sweep,
            colors: <Color>[
              tone.withValues(alpha: 0.75),
              tone,
            ],
            transform: GradientRotation(start),
          ).createShader(rect),
      );
      start += sweep;
    }

    if (donut) {
      final painter = TextPainter(
        text: TextSpan(
          text: total >= 1000
              ? '${(total / 1000).toStringAsFixed(1)}k'
              : total.round().toString(),
          style: series.label?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: series.onSurface,
          ),
        ),
        textDirection: textDirection,
      )..layout();
      painter.paint(
        canvas,
        centre - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  void _paintScatter(Canvas canvas, Size size) {
    final xs = series.points.map((p) => p.x ?? 0).toList();
    final ys = series.points.map((p) => p.value).toList();
    if (xs.isEmpty) return;

    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final spanX = maxX - minX == 0 ? 1 : maxX - minX;
    final spanY = maxY - minY == 0 ? 1 : maxY - minY;
    final plot = Size(size.width - 8, size.height - _axisHeight);

    // Faint axes, because a scatter without them is a cloud with no scale.
    final axis = Paint()
      ..color = series.grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, plot.height), Offset(plot.width, plot.height), axis);
    canvas.drawLine(const Offset(0, 0), Offset(0, plot.height), axis);

    final tone = series.toneAt(0);
    final shown = (series.points.length * progress).round();
    for (var i = 0; i < shown; i++) {
      final point = series.points[i];
      final position = Offset(
        4 + ((point.x ?? 0) - minX) / spanX * plot.width,
        plot.height - (point.value - minY) / spanY * plot.height,
      );
      canvas.drawCircle(
        position,
        3,
        Paint()
          // Translucent, so density shows as depth of colour. An opaque dot
          // hides every point underneath it and a dense cloud reads as sparse.
          ..color = tone.withValues(alpha: 0.42)
          ..style = PaintingStyle.fill,
      );
    }

    _paintAxisExtent(canvas, plot, minX, maxX, minY, maxY, size);
  }

  void _paintAxisExtent(
    Canvas canvas,
    Size plot,
    double minX,
    double maxX,
    double minY,
    double maxY,
    Size size,
  ) {
    void label(String text, Offset at, {bool rightAlign = false}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: series.label?.copyWith(color: series.onSurface),
        ),
        textDirection: textDirection,
      )..layout();
      painter.paint(
        canvas,
        rightAlign ? at - Offset(painter.width, 0) : at,
      );
    }

    String round(double value) => value.abs() >= 10
        ? value.round().toString()
        : value.toStringAsFixed(1);

    label(round(minX), Offset(0, size.height - _axisHeight + 4));
    label(
      round(maxX),
      Offset(plot.width, size.height - _axisHeight + 4),
      rightAlign: true,
    );
    label(round(maxY), const Offset(2, 0));
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.progress != progress ||
      old.touched != touched ||
      old.series.points != series.points ||
      old.style != style;
}
