import 'dart:io' show Platform;
import 'dart:ui' show Rect;

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
  /// Reads text from the image. [region], when given, is a normalised rectangle
  /// (0–1, top-left origin) to read *only* — so a letterhead or footer can be
  /// left out by reading just the body.
  Future<ScannedText> scan(String imagePath, {Rect? region});
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
  Future<ScannedText> scan(String imagePath, {Rect? region}) async {
    // ML Kit has no region-of-interest, so it reads the whole image; region is
    // honoured on the Apple path. (Android could pre-crop here later.)
    final input = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(input);
    return ScannedText(text: result.text, blockCount: result.blocks.length);
  }

  @override
  Future<void> dispose() => _recognizer.close();
}

/// Apple's Vision framework over a method channel — native, on-device, no
/// bundled model. The Swift side lives in `ios/Runner/AppleVisionOcr.swift`.
class AppleVisionTextScanner implements TextScanner {
  static const MethodChannel _channel = MethodChannel('app.medical/ocr');

  @override
  Future<ScannedText> scan(String imagePath, {Rect? region}) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'recognize',
      <String, Object?>{
        'path': imagePath,
        if (region != null)
          'region': <String, double>{
            'x': region.left,
            'y': region.top,
            'width': region.width,
            'height': region.height,
          },
      },
    );
    return ScannedText(
      text: (result?['text'] as String?) ?? '',
      blockCount: (result?['blocks'] as int?) ?? 0,
    );
  }

  @override
  Future<void> dispose() async {}
}
