import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// A minimal trend line.
///
/// Deliberately axis-free and label-free: at this size the useful question is
/// "is this going up, down or steady", not "what exactly was the value on
/// Tuesday". The precise numbers are always one tap away in the record, and a
/// chart that implies more precision than it can show is worse than none.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color,
    this.height = 36,
    this.showDots = true,
    this.fill = true,
  });

  /// Oldest first. Nulls are gaps, not zeroes — a missing observation must not
  /// draw a line down to the axis.
  final List<double?> values;
  final Color? color;
  final double height;
  final bool showDots;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final present = values.whereType<double>().toList();
    if (present.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            present.isEmpty ? 'No data yet' : 'Need two readings to trend',
            style: context.texts.labelSmall,
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: color ?? context.palette.primary,
          showDots: showDots,
          fill: fill,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.showDots,
    required this.fill,
  });

  final List<double?> values;
  final Color color;
  final bool showDots;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>().toList();
    if (present.length < 2) return;

    var min = present.reduce((a, b) => a < b ? a : b);
    var max = present.reduce((a, b) => a > b ? a : b);
    // A flat series would divide by zero; give it a nominal band so the line
    // renders through the middle instead of collapsing.
    if (max - min < 1e-9) {
      min -= 1;
      max += 1;
    }

    const padding = 3.0;
    final usableHeight = size.height - padding * 2;
    final stepX = values.length == 1 ? 0.0 : size.width / (values.length - 1);

    Offset? pointAt(int index) {
      final value = values[index];
      if (value == null) return null;
      final normalised = (value - min) / (max - min);
      return Offset(
        stepX * index,
        padding + usableHeight - normalised * usableHeight,
      );
    }

    // Split into runs so gaps break the line rather than bridging it.
    final runs = <List<Offset>>[];
    var current = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final point = pointAt(i);
      if (point == null) {
        if (current.length > 1) runs.add(current);
        current = <Offset>[];
      } else {
        current.add(point);
      }
    }
    if (current.length > 1) runs.add(current);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final run in runs) {
      final path = Path()..moveTo(run.first.dx, run.first.dy);
      for (final point in run.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }

      if (fill) {
        final area = Path.from(path)
          ..lineTo(run.last.dx, size.height)
          ..lineTo(run.first.dx, size.height)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                color.withValues(alpha: 0.18),
                color.withValues(alpha: 0.0),
              ],
            ).createShader(Offset.zero & size),
        );
      }

      canvas.drawPath(path, stroke);
    }

    if (showDots && runs.isNotEmpty) {
      final last = runs.last.last;
      canvas.drawCircle(last, 3.2, Paint()..color = color);
      canvas.drawCircle(
        last,
        3.2,
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}

/// Small labelled bar chart used for day-by-day counts.
///
/// Laid out with a flexible middle rather than an arithmetic bar height: the
/// labels are real text that grows with the system font scale, so computing
/// the bar as `height - constant` overflows on any device with larger type.
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.bars,
    this.height = 76,
    this.color,
  });

  /// Label plus count, oldest first.
  final List<({String label, int value})> bars;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final tone = color ?? palette.primary;
    final max = bars.fold<int>(0, (a, b) => b.value > a ? b.value : a);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars.map((bar) {
          final fraction = max == 0 ? 0.0 : bar.value / max;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: m.spaceXs / 2),
              child: Column(
                children: <Widget>[
                  Text(
                    bar.value == 0 ? '' : '${bar.value}',
                    maxLines: 1,
                    style: context.texts.labelSmall?.copyWith(
                      fontSize: 10,
                      color: tone,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: m.spaceXs / 2),
                  // Expanded + FractionallySizedBox: the bar takes whatever
                  // vertical space the labels leave, so it cannot overflow.
                  Expanded(
                    child: Stack(
                      children: <Widget>[
                        // A very faint track marks the slot without competing
                        // with the data. It must stay far lighter than any
                        // real bar — a solid track makes an empty day read as
                        // a full one, which is worse than drawing nothing.
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: palette.outline.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.bottomCenter,
                            heightFactor: fraction == 0 ? 0.06 : fraction,
                            child: Container(
                              decoration: BoxDecoration(
                                color: fraction == 0
                                    ? palette.outline.withValues(alpha: 0.55)
                                    : tone,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: m.spaceXs / 2),
                  Text(
                    bar.label,
                    maxLines: 1,
                    style: context.texts.labelSmall?.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
