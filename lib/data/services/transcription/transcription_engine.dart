import 'dart:io';

/// What a transcriber can be asked to do, and what it is allowed to promise.
///
/// The interface exists rather than calling a recogniser directly because the
/// choice of engine is a *clinical governance* decision, not a technical one.
/// A deployment that may not let audio leave the device needs a different
/// engine from one that may, and the note editor must not know which it got.
abstract interface class TranscriptionEngine {
  /// Shown to the user in Settings and recorded against the transcript, so a
  /// note always says what produced its text.
  String get name;

  /// Whether audio can leave the device when this engine runs.
  ///
  /// Not a footnote: the app's whole storage model rests on nothing being
  /// transmitted, and a transcriber that uploads is a different product. The
  /// UI refuses to offer an engine that returns true unless the operator has
  /// explicitly accepted it.
  bool get sendsAudioOffDevice;

  Future<TranscriptionAvailability> availability();

  /// Transcribes a 16 kHz mono WAV.
  ///
  /// [onProgress] reports 0–1 where the engine can estimate it. Long recordings
  /// on old hardware take longer than the recording itself, and a progress bar
  /// is the difference between "working" and "hung".
  Future<TranscriptionResult> transcribe(
    File wav, {
    void Function(double fraction)? onProgress,
  });

  Future<void> dispose();
}

/// Why an engine can or cannot run right now.
class TranscriptionAvailability {
  const TranscriptionAvailability.ready() : reason = null, isReady = true;

  const TranscriptionAvailability.unavailable(String this.reason)
      : isReady = false;

  final bool isReady;

  /// Written for a clinician, not a developer: it has to say what to do next.
  final String? reason;
}

class TranscriptionResult {
  const TranscriptionResult({
    required this.text,
    required this.engineName,
    required this.audioDuration,
    required this.processingTime,
    this.languageCode,
    this.segments = const <TranscriptSegment>[],
  });

  final String text;
  final String engineName;
  final Duration audioDuration;

  /// How long the transcription itself took. Surfaced because it is the number
  /// that decides whether the feature is usable on a given device.
  final Duration processingTime;

  final String? languageCode;
  final List<TranscriptSegment> segments;

  bool get isEmpty => text.trim().isEmpty;

  /// How much slower than real time this device transcribes. Above 1.0 means
  /// transcription takes longer than the recording.
  double get realTimeFactor => audioDuration.inMilliseconds == 0
      ? 0
      : processingTime.inMilliseconds / audioDuration.inMilliseconds;
}

class TranscriptSegment {
  const TranscriptSegment({
    required this.text,
    required this.start,
  });

  final String text;
  final Duration start;
}

/// The engine in use when no speech model has been installed.
///
/// Returning a null engine and null-checking at every call site would spread
/// the "is transcription set up?" question across the UI. This answers it in
/// one place, with a message that tells the user where to go.
class UnconfiguredTranscriptionEngine implements TranscriptionEngine {
  const UnconfiguredTranscriptionEngine([this.detail]);

  final String? detail;

  @override
  String get name => 'Not set up';

  @override
  bool get sendsAudioOffDevice => false;

  @override
  Future<TranscriptionAvailability> availability() async =>
      TranscriptionAvailability.unavailable(
        detail ??
            'No speech model is installed. Settings › Dictation › Speech '
                'recognition installs one, or loads one from a file if this '
                'device is kept off the network.',
      );

  @override
  Future<TranscriptionResult> transcribe(
    File wav, {
    void Function(double fraction)? onProgress,
  }) async {
    throw StateError('No transcription engine is configured');
  }

  @override
  Future<void> dispose() async {}
}
