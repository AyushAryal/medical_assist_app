import 'package:flutter/material.dart';

/// A border painted with a gradient rather than a single colour.
///
/// Flutter's [Border] takes one colour per side, so a multi-hue outline needs
/// its own painter. Kept here beside the badge that needs it rather than added
/// to the general design layer — a gradient outline is only ever correct for
/// marking generated content.
class GradientBoxBorder extends BoxBorder {
  const GradientBoxBorder({required this.gradient, this.width = 1});

  final Gradient gradient;
  final double width;

  @override
  BorderSide get bottom => BorderSide.none;

  @override
  BorderSide get top => BorderSide.none;

  @override
  bool get isUniform => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    final paint = Paint()
      ..strokeWidth = width
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke;

    if (borderRadius != null) {
      canvas.drawRRect(borderRadius.toRRect(rect).deflate(width / 2), paint);
    } else if (shape == BoxShape.circle) {
      canvas.drawCircle(rect.center, rect.shortestSide / 2 - width / 2, paint);
    } else {
      canvas.drawRect(rect.deflate(width / 2), paint);
    }
  }

  @override
  ShapeBorder scale(double t) =>
      GradientBoxBorder(gradient: gradient, width: width * t);
}
