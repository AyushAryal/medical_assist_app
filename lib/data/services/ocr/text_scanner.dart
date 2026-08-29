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
  Future<ScannedText> scan(String imagePath);
  Future<void> dispose();
}

/// ML Kit's Latin-script recogniser, bundled in the app and run offline.
class MlKitTextScanner implements TextScanner {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<ScannedText> scan(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(input);
    return ScannedText(text: result.text, blockCount: result.blocks.length);
  }

  @override
  Future<void> dispose() => _recognizer.close();
}
