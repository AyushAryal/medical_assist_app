import 'dart:io' show Platform;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Text lifted off an image.
class ScannedText {
  const ScannedText({required this.text, required this.blockCount});

  /// The recognised text, in reading order, blocks separated by newlines.
  final String text;

  /// How many separate text blocks were found — a rough measure of how much
  /// structure the page had.
  final int blockCount;

  bool get isEmpty => text.trim().isEmpty;
}

/// On-device optical character recognition.
///
/// A seam, so the recogniser can be faked in a test and swapped per platform.
/// Recognition runs entirely on the device — the image and its text never
/// leave it, the same rule the speech and language models follow. It is pure
/// extraction: it reads what is printed, it does not interpret it, so nothing
/// it produces is a clinical fact until a clinician files it.
abstract interface class TextScanner {
  /// Reads text from the image. [lasso], when given, is a freeform loop
  /// (normalised 0–1 points, top-left origin) drawn around the wanted text:
  /// recognition is limited to its bounds and then only the lines whose centre
  /// falls *inside* the loop are kept — so a letterhead in the same rectangle
  /// but outside the circle is excluded.
  Future<ScannedText> scan(String imagePath, {List<Offset>? lasso});
  Future<void> dispose();

  /// The best recogniser for this platform: Apple's native Vision engine on
  /// iOS (no bundled model, uses the OS), the bundled ML Kit model everywhere
  /// else. Same seam, so callers never branch on platform.
  factory TextScanner.platformDefault() {
    if (!kIsWeb && Platform.isIOS) return AppleVisionTextScanner();
    return MlKitTextScanner();
  }
}

/// ML Kit's Latin-script recogniser, bundled in the app and run offline.
class MlKitTextScanner implements TextScanner {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<ScannedText> scan(String imagePath, {List<Offset>? lasso}) async {
    // ML Kit has no region-of-interest; it reads the whole image. The lasso is
    // honoured on the Apple path. (Android could crop + filter later.)
    final input = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(input);
    return ScannedText(text: result.text, blockCount: result.blocks.length);
  }

  @override
  Future<void> dispose() => _recognizer.close();
}

/// Apple's Vision framework over a method channel — native, on-device, no
/// bundled model. The Swift side lives in `ios/Runner/AppDelegate.swift`.
class AppleVisionTextScanner implements TextScanner {
  static const MethodChannel _channel = MethodChannel('app.medical/ocr');

  @override
  Future<ScannedText> scan(String imagePath, {List<Offset>? lasso}) async {
    final bounds = lasso == null ? null : _boundsOf(lasso);
    final result = await _channel.invokeMapMethod<String, Object?>(
      'recognize',
      <String, Object?>{
        'path': imagePath,
        if (bounds != null)
          'region': <String, double>{
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.width,
            'height': bounds.height,
          },
      },
    );

    // No loop → use the whole-image text as-is.
    if (lasso == null) {
      return ScannedText(
        text: (result?['text'] as String?) ?? '',
        blockCount: (result?['blocks'] as int?) ?? 0,
      );
    }

    // Keep only lines whose centre is inside the drawn loop, not just its
    // bounding rectangle.
    final lines = (result?['lines'] as List<Object?>?) ?? const <Object?>[];
    final kept = <String>[];
    for (final entry in lines) {
      if (entry is! Map) continue;
      final x = (entry['x'] as num).toDouble();
      final y = (entry['y'] as num).toDouble();
      final w = (entry['w'] as num).toDouble();
      final h = (entry['h'] as num).toDouble();
      final centre = Offset(x + w / 2, y + h / 2);
      if (_inside(centre, lasso)) kept.add(entry['text'] as String);
    }
    return ScannedText(text: kept.join('\n'), blockCount: kept.length);
  }

  static Rect _boundsOf(List<Offset> points) {
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    const pad = 0.01;
    return Rect.fromLTRB(
      (minX - pad).clamp(0.0, 1.0),
      (minY - pad).clamp(0.0, 1.0),
      (maxX + pad).clamp(0.0, 1.0),
      (maxY + pad).clamp(0.0, 1.0),
    );
  }

  /// Ray-casting point-in-polygon over the loop's points.
  static bool _inside(Offset p, List<Offset> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i];
      final b = poly[j];
      final intersects = (a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (intersects) inside = !inside;
    }
    return inside;
  }

  @override
  Future<void> dispose() async {}
}
