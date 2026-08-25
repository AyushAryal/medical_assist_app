/// Voice visualisation for dictation.
///
/// The bar chart this replaces was accurate and unpleasant: it read as a
/// spectrum analyser, which is an engineering instrument, and it made a
/// clinician dictating into a patient record look like they were operating
/// equipment. Flowing bands read as *listening*.
///
/// It is still driven by the real microphone level, not by a decorative loop.
/// That matters: the one job this display has is to let someone confirm the
/// microphone is picking them up **before** they trust it with a consultation
/// they will not repeat. A pretty animation that moved regardless of input
/// would destroy exactly that, so silence is drawn as a flat line and nothing
/// else.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// Layered bands whose height follows the live input level.
class SiriWaveform extends StatefulWidget {
  const SiriWaveform({
    super.key,
    required this.level,
    required this.active,
    this.height = 110,
  });

  /// Current input level, 0–1.
  final double level;

  /// False parks the waves flat rather than idling them, so "not listening" is
  /// visually unmistakable.
  final bool active;

  final double height;

  @override
  State<SiriWaveform> createState() => _SiriWaveformState();
}

class _SiriWaveformState extends State<SiriWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  /// Where the level is heading, from the microphone.
  double _target = 0;

  /// Where the drawing currently is. Interpolated toward [_target] once per
  /// frame.
  double _smoothed = 0;

  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Smoothing is advanced per *frame*, not per rebuild. Doing it in
    // didUpdateWidget was the source of the glitching: audio chunks arrive
    // irregularly, so the level moved in visible steps between them and
    // froze whenever the microphone went quiet — exactly at the pickup and
    // pause moments where the motion is most looked at.
    _controller
      ..addListener(_advance)
      ..repeat();
  }

  void _advance() {
    final now = _controller.lastElapsedDuration ?? Duration.zero;
    final dt = ((now - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = now;
    if (dt <= 0) return;

    // Frame-rate independent easing. Rise quickly, fall slowly — matching how
    // a voice is actually perceived, and stopping the bands collapsing
    // between syllables.
    final rate = _target > _smoothed ? 14.0 : 4.0;
    final factor = 1 - math.exp(-rate * dt);
    final next = _smoothed + (_target - _smoothed) * factor;

    // Only repaint when it would actually differ on screen.
    if ((next - _smoothed).abs() > 0.0005) {
      setState(() => _smoothed = next);
    } else {
      _smoothed = next;
    }
  }

  @override
  void didUpdateWidget(SiriWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A little headroom so ordinary speech reaches most of the height rather
    // than hovering near the baseline.
    _target = widget.active ? (widget.level * 1.35).clamp(0.0, 1.0) : 0.0;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_advance)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _WavePainter(
              phase: reduced ? 0 : _controller.value * 2 * math.pi,
              level: reduced ? widget.level.clamp(0.0, 1.0) : _smoothed,
              colors: <Color>[
                palette.accent,
                palette.primary,
                palette.info,
                palette.accent,
              ],
              trackColor: palette.onSurfaceMuted,
              bloom: !reduced,
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.phase,
    required this.level,
    required this.colors,
    required this.trackColor,
    required this.bloom,
  });

  final double phase;
  final double level;
  final List<Color> colors;
  final Color trackColor;
  final bool bloom;

  /// Below this the display is a resting line. Not zero: microphone noise
  /// never reaches zero, and a line that quivers at rest would suggest the
  /// microphone is hearing something when it is not.
  static const double _restThreshold = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;

    // The resting line is always drawn, and the bands fade in over it. Doing
    // it this way rather than switching between two states is what removes
    // the pop at the moment speech starts.
    final restOpacity = (1 - level / (_restThreshold * 4)).clamp(0.0, 1.0);
    if (restOpacity > 0.01) {
      canvas.drawLine(
        Offset(size.width * 0.06, midY),
        Offset(size.width * 0.94, midY),
        Paint()
          ..color = trackColor.withValues(alpha: 0.32 * restOpacity)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    if (level < _restThreshold) return;

    // Four bands at incommensurate frequencies and speeds. Differing
    // frequencies are what stop them reading as one thick line — they drift in
    // and out of alignment, which is the organic quality a bar chart lacks.
    const bands = <({double frequency, double speed, double scale, double
        width})>[
      (frequency: 1.0, speed: 1.0, scale: 1.00, width: 3.4),
      (frequency: 1.7, speed: -1.35, scale: 0.74, width: 2.6),
      (frequency: 2.6, speed: 0.82, scale: 0.52, width: 2.0),
      (frequency: 3.9, speed: -0.55, scale: 0.34, width: 1.5),
    ];

    for (var i = 0; i < bands.length; i++) {
      final band = bands[i];
      final amplitude = midY * 0.80 * level * band.scale;
      final path = Path();
      final mirror = <Offset>[];

      for (var x = 0.0; x <= size.width; x += 2) {
        final t = x / size.width;
        // Envelope pinned at both ends, so the bands taper to a point rather
        // than being sliced off by the edge of the box.
        final envelope = math.pow(math.sin(t * math.pi), 1.3).toDouble();
        final offset =
            math.sin(t * band.frequency * 2 * math.pi + phase * band.speed) *
                amplitude *
                envelope;
        final y = midY + offset;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        mirror.add(Offset(x, midY - offset));
      }

      final shader = LinearGradient(
        colors: <Color>[
          colors[i % colors.length].withValues(alpha: 0),
          colors[i % colors.length],
          colors[(i + 1) % colors.length],
          colors[(i + 1) % colors.length].withValues(alpha: 0),
        ],
        stops: const <double>[0, 0.22, 0.78, 1],
      ).createShader(Offset.zero & size);

      // A soft bloom under the stroke. Drawn first and wider, so the line
      // sits inside its own glow.
      if (bloom && i < 2) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = band.width * 3.2
            ..strokeCap = StrokeCap.round
            ..shader = shader
            ..color = Colors.white.withValues(alpha: 0.35 * level)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = band.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = shader,
      );

      // The mirrored counterpart, fainter — it is what makes the shape read as
      // a voice rather than as a graph.
      if (i < 3) {
        final reflection = Path()..moveTo(mirror.first.dx, mirror.first.dy);
        for (final point in mirror.skip(1)) {
          reflection.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(
          reflection,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = band.width * 0.7
            ..strokeCap = StrokeCap.round
            ..shader = shader
            ..color = Colors.white.withValues(alpha: 0.45),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.phase != phase || old.level != level || old.bloom != bloom;
}
