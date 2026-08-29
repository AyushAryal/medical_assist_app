import 'dart:io' show Platform;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'table_reconstruction.dart';

/// Text lifted off an image.
class ScannedText {
  ScannedText({
    required this.text,
    required this.blockCount,
    String? markdown,
  }) : markdown = markdown ?? text;

  /// The recognised text, in reading order, blocks separated by newlines.
  final String text;

  /// How many separate text blocks were found — a rough measure of how much
  /// structure the page had.
  final int blockCount;

  /// The text with layout preserved: a Markdown table when the page was laid
  /// out in columns, otherwise the same as [text]. Where the recogniser gives
  /// no positions (ML Kit) this is just [text].
  final String markdown;

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
    // Recognise the whole (correctly-oriented) image, then keep only the lines
    // inside the loop. Deliberately no regionOfInterest: a ROI plus an image
    // orientation do not share a coordinate frame cleanly, which shifted the
    // read area off from where the loop was drawn. Per-line boxes come back in
    // the same normalised, oriented, top-left space as the loop, so filtering
    // by polygon is exact.
    final result = await _channel.invokeMapMethod<String, Object?>(
      'recognize',
      <String, Object?>{'path': imagePath},
    );

    // Build the line boxes, keeping only those inside the loop when one is set.
    final raw = (result?['lines'] as List<Object?>?) ?? const <Object?>[];
    final lines = <OcrLine>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final line = OcrLine(
        text: entry['text'] as String,
        x: (entry['x'] as num).toDouble(),
        y: (entry['y'] as num).toDouble(),
        w: (entry['w'] as num).toDouble(),
        h: (entry['h'] as num).toDouble(),
      );
      if (lasso == null || _inside(Offset(line.cx, line.cy), lasso)) {
        lines.add(line);
      }
    }

    if (lines.isEmpty) {
      // Fall back to the native joined text (e.g. nothing had boxes).
      return ScannedText(
        text: (result?['text'] as String?) ?? '',
        blockCount: (result?['blocks'] as int?) ?? 0,
      );
    }

    final ordered = <OcrLine>[...lines]
      ..sort((a, b) => a.cy != b.cy ? a.cy.compareTo(b.cy) : a.cx.compareTo(b.cx));
    return ScannedText(
      text: ordered.map((l) => l.text).join('\n'),
      blockCount: lines.length,
      markdown: reconstructMarkdown(lines),
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
