/// A scrubbable waveform for a recorded voice note.
///
/// A progress bar answers "how far through am I" and nothing else. The
/// question a clinician actually has in front of an attached recording is
/// "how long is this, and where is the part I want" — and a shape answers both
/// at a glance in a way a bar cannot.
///
/// The curve is **derived from the file path, not from the audio**. Decoding a
/// recording to draw it would mean reading and decompressing the whole file
/// every time a note is opened, on a device that may hold hundreds of them.
/// The shape is therefore decorative and deliberately not presented as a
/// rendering of the sound — it is a consistent, recognisable fingerprint for
/// each recording, which is what makes it useful for scrubbing back to a spot.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

class PlaybackWaveform extends StatelessWidget {
  const PlaybackWaveform({
    super.key,
    required this.progress,
    required this.playing,
    required this.seed,
    this.onSeek,
    this.height = 26,
    this.selection,
    this.onSelect,
  });

  /// 0–1 through the recording.
  final double progress;
  final bool playing;

  /// Stable input for the generated shape, so one recording always looks the
  /// same. The file path is used because it never changes for a given file.
  final String seed;

  /// Called with a 0–1 position when the bar is tapped or dragged.
  final ValueChanged<double>? onSeek;

  final double height;

  /// A highlighted stretch, as fractions. Used when a region is being marked
  /// for removal.
  final (double, double)? selection;

  /// Called as a stretch is dragged out. Non-null puts the widget into
  /// selection mode, where dragging marks rather than seeks.
  final void Function(double start, double end)? onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        void seekTo(Offset local) {
          final handler = onSeek;
          if (handler == null) return;
          handler((local.dx / constraints.maxWidth).clamp(0.0, 1.0));
        }

        double fractionAt(Offset local) =>
            (local.dx / constraints.maxWidth).clamp(0.0, 1.0);

        var anchor = 0.0;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onSelect == null
              ? (details) => seekTo(details.localPosition)
              : null,
          onHorizontalDragStart: onSelect == null
              ? null
              : (details) {
                  anchor = fractionAt(details.localPosition);
                  onSelect!(anchor, anchor);
                },
          onHorizontalDragUpdate: (details) {
            if (onSelect == null) {
              seekTo(details.localPosition);
              return;
            }
            final current = fractionAt(details.localPosition);
            onSelect!(
              anchor < current ? anchor : current,
              anchor < current ? current : anchor,
            );
          },
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _PlaybackPainter(
                progress: progress,
                bars: _barsFor(seed),
                played: palette.primary,
                remaining: palette.onSurfaceMuted,
                accent: palette.accent,
                playing: playing,
                selection: selection,
                selectionTint: palette.critical,
              ),
            ),
          ),
        );
      },
    );
  }

  /// A stable pseudo-random envelope for this recording.
  ///
  /// Shaped like speech rather than like noise: a slow rise and fall with
  /// smaller variation on top, and tapered at both ends so the curve closes
  /// to a point instead of being sliced off by the edge of the strip.
  static List<double> _barsFor(String seed) {
    final random = math.Random(seed.hashCode);
    const count = 60;
    final raw = <double>[
      for (var i = 0; i < count; i++)
        () {
          final t = i / (count - 1);
          final envelope = 0.45 + 0.4 * math.sin(t * math.pi * 2.3 + 0.7).abs();
          final taper = math.sin(t * math.pi).clamp(0.0, 1.0);
          return envelope * (0.55 + random.nextDouble() * 0.45) * taper;
        }(),
    ];

    // One smoothing pass over the samples themselves. Smoothing the curve
    // alone leaves the spikes visible as bulges; smoothing the data first is
    // what makes it read as a voice rather than as filtered noise.
    return <double>[
      for (var i = 0; i < raw.length; i++)
        () {
          final previous = raw[math.max(0, i - 1)];
          final next = raw[math.min(raw.length - 1, i + 1)];
          return ((previous + raw[i] * 2 + next) / 4).clamp(0.04, 1.0);
        }(),
    ];
  }
}

class _PlaybackPainter extends CustomPainter {
  _PlaybackPainter({
    required this.progress,
    required this.bars,
    required this.played,
    required this.remaining,
    required this.accent,
    required this.playing,
    this.selection,
    this.selectionTint,
  });

  final double progress;
  final List<double> bars;
  final Color played;
  final Color remaining;
  final Color accent;
  final bool playing;
  final (double, double)? selection;
  final Color? selectionTint;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final midY = size.height / 2;
    final step = size.width / (bars.length - 1);

    // A smooth envelope rather than a row of blocks. Bars read as a bar chart,
    // which is a measuring instrument; a curve reads as sound. The shape is the
    // same data either way — only one of them looks like something you would
    // scrub through.
    final upper = Path();
    final points = <Offset>[
      for (var i = 0; i < bars.length; i++)
        Offset(step * i, midY - bars[i] * (midY - 1)),
    ];

    upper.moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      // Midpoint quadratic smoothing: each control point is a sample and the
      // curve passes through the midpoints between them. Cheap, stable, and it
      // never overshoots the way a cubic fit through noisy samples does.
      final current = points[i];
      final next = points[i + 1];
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      upper.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    upper.lineTo(points.last.dx, points.last.dy);

    // Mirror it to close the shape around the centre line.
    final shape = Path.from(upper);
    for (var i = points.length - 1; i >= 0; i--) {
      final mirrored = Offset(points[i].dx, midY + (midY - points[i].dy));
      if (i == points.length - 1) {
        shape.lineTo(mirrored.dx, mirrored.dy);
      } else {
        final next = Offset(
          points[i + 1].dx,
          midY + (midY - points[i + 1].dy),
        );
        final mid = Offset(
          (mirrored.dx + next.dx) / 2,
          (mirrored.dy + next.dy) / 2,
        );
        shape.quadraticBezierTo(next.dx, next.dy, mid.dx, mid.dy);
      }
    }
    shape.close();

    final playedUntil = size.width * progress;

    // Unplayed first, then the played portion clipped over it. Two fills of one
    // shape rather than two shapes, so the boundary is exactly at the playhead
    // instead of snapping to whichever sample is nearest.
    canvas.drawPath(
      shape,
      Paint()..color = remaining.withValues(alpha: 0.28),
    );

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, playedUntil, size.height));
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[played, accent],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();

    // The stretch marked for removal, drawn over everything so it is
    // unmistakable which part is about to go.
    if (selection case final (double, double) range
        when selectionTint != null && range.$2 > range.$1) {
      final rect = Rect.fromLTRB(
        size.width * range.$1,
        0,
        size.width * range.$2,
        size.height,
      );
      canvas.drawRect(
        rect,
        Paint()..color = selectionTint!.withValues(alpha: 0.28),
      );
      for (final x in <double>[rect.left, rect.right]) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = selectionTint!
            ..strokeWidth = 1.5,
        );
      }
    }

    // The playhead. A hairline rather than a knob: the shape is the affordance,
    // and a knob on a 26px strip covers the very detail being scrubbed for.
    if (progress > 0 && progress < 1) {
      canvas.drawLine(
        Offset(playedUntil, 2),
        Offset(playedUntil, size.height - 2),
        Paint()
          ..color = accent
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_PlaybackPainter old) =>
      old.progress != progress ||
      old.playing != playing ||
      old.bars != bars ||
      old.selection != selection;
}
