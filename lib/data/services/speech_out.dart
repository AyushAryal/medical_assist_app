import 'package:flutter/services.dart';

/// Reads text aloud through the platform speech synthesiser.
///
/// A thin channel to the system voice (iOS `AVSpeechSynthesizer`). Best-effort:
/// where no synthesiser is wired (non-Apple, for now) the calls are no-ops, so
/// a caller can always offer "speak" and simply get silence rather than an
/// error. Nothing here is on the critical path.
abstract final class SpeechOut {
  static const MethodChannel _channel = MethodChannel('app.medical/tts');

  static Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<bool>('speak', <String, Object?>{'text': text});
    } on Object {
      // No synthesiser on this platform — silence is an acceptable outcome.
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } on Object {
      // Nothing playing / no channel.
    }
  }

  /// Quality of the best installed voice: 0 none, 1 default (the robotic
  /// compact voice), 2 enhanced, 3 premium. Lets the UI nudge the user to
  /// download a natural voice when only the default is present.
  static Future<int> bestVoiceQuality() async {
    try {
      return await _channel.invokeMethod<int>('bestVoiceQuality') ?? 0;
    } on Object {
      return 0;
    }
  }
}
