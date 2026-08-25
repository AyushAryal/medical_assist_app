import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../audio/wav.dart';
import 'speech_model.dart';
import 'transcription_engine.dart';

/// Whisper, running entirely on the device through sherpa-onnx.
///
/// Two properties are the whole reason this is the engine the app ships with:
/// **no audio leaves the device**, and it works in a clinic with no signal.
/// Both matter more here than the accuracy a larger cloud model would give,
/// because a transcript is a draft the clinician edits, whereas a patient's
/// voice leaving the building is not undoable.
///
/// Inference runs in a spawned isolate. Whisper tiny takes on the order of
/// seconds per minute of audio on current hardware and considerably longer on
/// an older device, and all of it is blocking native work — on the UI isolate
/// it would freeze the app mid-consultation.
class WhisperTranscriptionEngine implements TranscriptionEngine {
  WhisperTranscriptionEngine({
    required this.models,
    required this.model,
    this.threads = 2,
  });

  final SpeechModelManager models;
  final SpeechModel model;

  /// Two threads is the useful setting on a phone: the encoder parallelises,
  /// but going wider competes with the UI isolate and with whatever else the
  /// device is doing, and on a four-core budget SoC it makes things slower.
  final int threads;

  @override
  String get name => model.name;

  @override
  bool get sendsAudioOffDevice => false;

  @override
  Future<TranscriptionAvailability> availability() async {
    final installed = await models.installed(model);
    if (installed == null) {
      final onDisk = await models.bytesOnDisk(model);
      return TranscriptionAvailability.unavailable(
        onDisk == 0
            ? '${model.name} is not installed yet (${model.sizeLabel}).'
            : 'The ${model.name} install is incomplete — '
                '${(onDisk / (1024 * 1024)).round()} MB of '
                '${model.sizeLabel} is on the device.',
      );
    }
    return const TranscriptionAvailability.ready();
  }

  @override
  Future<TranscriptionResult> transcribe(
    File wav, {
    void Function(double fraction)? onProgress,
  }) async {
    final installed = await models.installed(model);
    if (installed == null) {
      throw StateError('${model.name} is not installed');
    }

    // Decoding the WAV here rather than in the isolate keeps the isolate
    // payload to plain data and keeps file-format errors on this side of the
    // boundary, where they can be reported properly.
    final audio = Wav.decode(await wav.readAsBytes());
    if (audio.sampleRate != _requiredSampleRate) {
      throw StateError(
        'Whisper needs $_requiredSampleRate Hz audio; this file is '
        '${audio.sampleRate} Hz.',
      );
    }

    onProgress?.call(0.05);
    final started = DateTime.now();

    final text = await Isolate.run(
      () => _transcribeInIsolate(
        _IsolateRequest(
          encoderPath: installed.encoderPath,
          decoderPath: installed.decoderPath,
          tokensPath: installed.tokensPath,
          samples: audio.samples,
          sampleRate: audio.sampleRate,
          threads: threads,
        ),
      ),
      debugName: 'whisper-transcribe',
    );

    onProgress?.call(1);

    return TranscriptionResult(
      text: _tidy(text),
      engineName: '${model.name} (on device)',
      audioDuration: audio.duration,
      processingTime: DateTime.now().difference(started),
      languageCode: model.isMultilingual ? null : 'en',
    );
  }

  @override
  Future<void> dispose() async {
    // Nothing is retained between calls: the recogniser is created and freed
    // inside the isolate. Holding a loaded model would keep ~100 MB resident
    // for a feature used a few times an hour, and the app is expected to share
    // a device with a camera and a browser.
  }

  static const int _requiredSampleRate = 16000;

  /// Whisper emits a leading space and, on silence, hallucinated boilerplate.
  ///
  /// The blank-audio phrases are a documented artefact of the training data:
  /// fed near-silence, the model reaches for the most common caption in its
  /// corpus. Left in, they would be inserted into a clinical note as though
  /// the clinician had dictated them.
  static String _tidy(String raw) {
    var text = raw.trim();
    for (final artefact in _hallucinations) {
      if (text.toLowerCase() == artefact) return '';
    }
    return text;
  }

  static const Set<String> _hallucinations = <String>{
    'thank you.',
    'thanks for watching!',
    'thank you for watching.',
    'thank you for watching!',
    'you',
    '(buzzing)',
    '[blank_audio]',
    'subs by www.zeoranger.co.uk',
  };
}

/// Everything the isolate needs, all of it sendable.
class _IsolateRequest {
  const _IsolateRequest({
    required this.encoderPath,
    required this.decoderPath,
    required this.tokensPath,
    required this.samples,
    required this.sampleRate,
    required this.threads,
  });

  final String encoderPath;
  final String decoderPath;
  final String tokensPath;
  final Int16List samples;
  final int sampleRate;
  final int threads;
}

/// Runs in the spawned isolate. Must not touch anything from the parent beyond
/// [request], and must free the native recogniser on every path — a leaked
/// one holds the whole model in memory for the life of the process.
String _transcribeInIsolate(_IsolateRequest request) {
  // Bindings are per-isolate, so this call is required here even though the
  // parent isolate has already made it.
  sherpa.initBindings();

  final config = sherpa.OfflineRecognizerConfig(
    model: sherpa.OfflineModelConfig(
      whisper: sherpa.OfflineWhisperModelConfig(
        encoder: request.encoderPath,
        decoder: request.decoderPath,
      ),
      tokens: request.tokensPath,
      modelType: 'whisper',
      numThreads: request.threads,
      debug: false,
    ),
  );

  sherpa.OfflineRecognizer? recognizer;
  sherpa.OfflineStream? stream;
  try {
    recognizer = sherpa.OfflineRecognizer(config);
    stream = recognizer.createStream();
    stream.acceptWaveform(
      samples: _toFloat32(request.samples),
      sampleRate: request.sampleRate,
    );
    recognizer.decode(stream);
    return recognizer.getResult(stream).text;
  } finally {
    stream?.free();
    recognizer?.free();
  }
}

/// 16-bit PCM to the normalised floats the recogniser expects.
///
/// Divides by 32768 rather than 32767 so the conversion is exact in binary and
/// the most negative sample maps to exactly -1.0 instead of just past it.
Float32List _toFloat32(Int16List samples) {
  final out = Float32List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    out[i] = samples[i] / 32768.0;
  }
  return out;
}
