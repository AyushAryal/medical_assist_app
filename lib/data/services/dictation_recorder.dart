import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/utils/ids.dart';
import 'audio/voice_activity_detector.dart';
import 'audio/wav.dart';

/// How a finished dictation is stored.
enum DictationQuality {
  /// 16 kHz — the rate speech recognition needs. Keep this where the audio may
  /// be re-transcribed later or where a second listener may need to check a
  /// drug name against what was actually said.
  full,

  /// 8 kHz, half the size. Telephone bandwidth: entirely intelligible, and
  /// noticeably duller. Transcription still runs at 16 kHz before the
  /// downsample, so accuracy is unaffected — only later re-transcription of the
  /// stored file would be.
  compact,
}

extension DictationQualityX on DictationQuality {
  String get label => switch (this) {
        DictationQuality.full => 'Full (16 kHz)',
        DictationQuality.compact => 'Compact (8 kHz)',
      };

  String get detail => switch (this) {
        DictationQuality.full =>
          'Keeps the recording at the rate speech recognition uses, so it can '
              'be transcribed again later.',
        DictationQuality.compact =>
          'Half the file size at telephone quality. Clear enough to listen '
              'back to; not ideal for re-transcribing.',
      };

  int get storedSampleRate =>
      this == DictationQuality.full ? 16000 : 8000;
}

/// What the recorder is doing, for a UI that has to be honest about it.
enum DictationState { idle, recording, processing }

/// Live feedback while recording.
class DictationLevel {
  const DictationLevel({
    required this.elapsed,
    required this.recentLevels,
    required this.isSpeaking,
    required this.silenceRun,
  });

  final Duration elapsed;

  /// Recent frame energies normalised to 0–1, newest last. Drives the
  /// waveform, which exists for one reason: it is the only way a clinician can
  /// tell a working microphone from a muted one *before* trusting it with a
  /// consultation they will not repeat.
  final List<double> recentLevels;

  final bool isSpeaking;

  /// The most recent frame energy, 0–1. What the waveform follows.
  double get current => recentLevels.isEmpty ? 0 : recentLevels.last;

  /// How long the current silence has run. Shown so the user understands that
  /// the pause they are taking is being dropped, rather than discovering it
  /// afterwards.
  final Duration silenceRun;
}

/// The finished recording.
class DictationCapture {
  const DictationCapture({
    required this.file,
    this.originalFile,
    required this.duration,
    required this.originalDuration,
    required this.storedBytes,
    required this.untrimmedBytes,
    required this.sampleRate,
    required this.samples,
  });

  /// A 16-bit mono WAV, silence removed.
  final File file;

  /// The untrimmed recording, when the operator asked for it to be kept.
  /// Null otherwise, which is the default.
  final File? originalFile;

  /// Length after trimming — what a listener will actually hear.
  final Duration duration;

  /// Length before trimming, i.e. how long the clinician held the button.
  final Duration originalDuration;

  final int storedBytes;

  /// What the file would have taken untrimmed, for reporting the saving.
  final int untrimmedBytes;

  final int sampleRate;

  /// The trimmed 16 kHz samples, kept in memory so transcription does not have
  /// to read the file back — and so it can still run at full rate when the
  /// stored copy has been downsampled.
  final Int16List samples;

  Duration get removed => originalDuration - duration;

  double get savedFraction =>
      untrimmedBytes == 0 ? 0 : 1 - (storedBytes / untrimmedBytes);

  /// True when the untrimmed recording was kept as well.
  bool get hasOriginal => originalFile != null;

  /// One line for the UI: what was cut, and what it saved.
  String get savingSummary {
    if (removed.inSeconds < 1) {
      return 'No silence worth removing — a continuous dictation.';
    }
    final seconds = removed.inSeconds;
    final removedLabel = seconds >= 60
        ? '${seconds ~/ 60}m ${(seconds % 60).toString().padLeft(2, '0')}s'
        : '${seconds}s';
    return 'Removed $removedLabel of silence · '
        '${(savedFraction * 100).round()}% smaller';
  }
}

/// Records dictation, drops the silence, and hands back speech-only audio.
///
/// Capturing a PCM stream and assembling the file here — rather than letting
/// the platform encode straight to a compressed file — is what makes trimming
/// possible at all. The recorder's own pause/resume cannot do it: while paused
/// the microphone is released, so there is nothing to measure and nothing that
/// could decide when to start again. Owning the samples means the gate can look
/// at the audio it is deciding about.
///
/// The trade is that the output is uncompressed. Trimming pays for a good part
/// of that, [DictationQuality.compact] pays for the rest, and what really pays
/// for it is the transcript: once a dictation has been turned into text, the
/// audio is a fallback that is rarely opened.
class DictationRecorder extends ChangeNotifier {
  DictationRecorder({
    AudioRecorder? recorder,
    VoiceActivityDetector? detector,
    this.quality = DictationQuality.full,
    this.keepOriginal = false,
  })  : _recorder = recorder ?? AudioRecorder(),
        _detector = detector ?? VoiceActivityDetector(sampleRate: _sampleRate);

  static const int _sampleRate = 16000;

  /// How much of the waveform is kept for display — about three seconds.
  static const int _displayFrames = 60;

  final AudioRecorder _recorder;
  final VoiceActivityDetector _detector;

  DictationQuality quality;

  /// Also keep the untrimmed recording alongside the trimmed one.
  ///
  /// Off by default, and that default is the considered position rather than
  /// laziness: trimming is biased toward keeping audio, the transcript is
  /// reviewed before it can reach a note, and the original doubles what every
  /// dictation costs on a device holding a whole clinic's records.
  ///
  /// It exists because there is a real case for the other choice. A dictation
  /// is evidence, and an operator who expects a transcript to be disputed —
  /// or who does not yet trust the trimming on their hardware — should be able
  /// to keep exactly what the microphone heard. That judgement belongs to the
  /// deployment, not to this class.
  bool keepOriginal;

  DictationState _state = DictationState.idle;
  StreamSubscription<Uint8List>? _subscription;
  final List<Int16List> _chunks = <Int16List>[];
  int _sampleCount = 0;
  DateTime? _startedAt;
  Timer? _ticker;

  final List<double> _displayLevels = <double>[];
  bool _isSpeaking = false;
  DateTime? _silenceSince;

  DictationState get state => _state;
  bool get isRecording => _state == DictationState.recording;

  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : Duration(milliseconds: (_sampleCount * 1000 / _sampleRate).round());

  DictationLevel get level => DictationLevel(
        elapsed: elapsed,
        recentLevels: List<double>.unmodifiable(_displayLevels),
        isSpeaking: _isSpeaking,
        silenceRun: _silenceSince == null
            ? Duration.zero
            : DateTime.now().difference(_silenceSince!),
      );

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<bool> start() async {
    if (_state != DictationState.idle) return _state == DictationState.recording;
    if (!await _recorder.hasPermission()) return false;

    _chunks.clear();
    _sampleCount = 0;
    _displayLevels.clear();
    _isSpeaking = false;
    _silenceSince = null;

    final stream = await _recorder.startStream(
      const RecordConfig(
        // Raw PCM: the only encoder whose output this class can inspect.
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        // Speech, on a device held at arm's length in a room with other people
        // in it.
        //
        // Auto-gain is off, and that is a considered trade rather than an
        // oversight. It makes a quiet voice louder — but it does so by lifting
        // the *pauses* toward the speech, which collapses the very contrast
        // silence trimming depends on. Between "slightly quieter recording"
        // and "trimming that does nothing", the recording wins. The detector
        // adapts to what range remains regardless, so this is belt and braces.
        //
        // Noise suppression stays on: it removes the fan the gate would
        // otherwise have to work around, and it lowers the floor rather than
        // raising it. Echo cancellation is off — there is no loudspeaker in
        // this path and it only costs input level.
        autoGain: false,
        noiseSuppress: true,
        echoCancel: false,
      ),
    );

    _startedAt = DateTime.now();
    _state = DictationState.recording;
    _subscription = stream.listen(
      _onAudio,
      onError: (Object _) {
        // A stream error mid-recording must not strand the UI in "recording"
        // with a dead microphone.
        unawaited(cancel());
      },
      cancelOnError: true,
    );

    // Drives the elapsed counter between audio callbacks, so the timer keeps
    // moving even if the platform delivers audio in large infrequent buffers.
    _ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => notifyListeners(),
    );

    notifyListeners();
    return true;
  }

  void _onAudio(Uint8List bytes) {
    final samples = Wav.pcm16FromBytes(bytes);
    if (samples.isEmpty) return;

    _chunks.add(samples);
    _sampleCount += samples.length;

    // Live analysis is only for the waveform and the speaking indicator. The
    // decision that matters is made once at the end over the whole recording,
    // where the gate can see the quietest part of the room — which a streaming
    // decision cannot, because at the moment of the first word it has not
    // heard the pause that follows it.
    final analysis = _detector.analyse(samples);
    if (analysis.frameDb.isNotEmpty) {
      for (final db in analysis.frameDb) {
        // -60..0 dBFS mapped to 0..1 for display.
        _displayLevels.add(((db + 60) / 60).clamp(0.0, 1.0));
      }
      while (_displayLevels.length > _displayFrames) {
        _displayLevels.removeAt(0);
      }

      final speaking = analysis.speechFraction > 0.3;
      if (speaking) {
        _isSpeaking = true;
        _silenceSince = null;
      } else if (_isSpeaking || _silenceSince == null) {
        _isSpeaking = false;
        _silenceSince ??= DateTime.now();
      }
    }

    notifyListeners();
  }

  /// Stops, trims, writes the file, and returns it.
  ///
  /// Returns null when nothing usable was captured — too short, or all silence.
  Future<DictationCapture?> stop() async {
    if (_state != DictationState.recording) return null;

    _state = DictationState.processing;
    notifyListeners();

    _ticker?.cancel();
    _ticker = null;
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();

    final captured = _concatenate();
    _chunks.clear();
    _startedAt = null;

    if (captured.isEmpty) {
      _state = DictationState.idle;
      notifyListeners();
      return null;
    }

    // Trimming a long recording is tens of milliseconds of arithmetic per
    // minute of audio, but it is done off the UI isolate anyway: on a six-year
    // old phone a ten-minute dictation is enough to drop frames, and this runs
    // at exactly the moment the clinician is waiting to see their words.
    final trimmed = await compute(_trimInBackground, (
      samples: captured,
      sampleRate: _sampleRate,
    ));

    if (trimmed.samples.isEmpty) {
      _state = DictationState.idle;
      notifyListeners();
      return null;
    }

    final stored = quality == DictationQuality.compact
        ? Wav.downsampleByTwo(trimmed.samples)
        : trimmed.samples;

    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, '${newId()}.wav'));
    await file.writeAsBytes(
      Wav.encode(stored, sampleRate: quality.storedSampleRate),
      flush: true,
    );

    // The untrimmed capture, at full rate. Written second and only on request,
    // so the ordinary path never pays for it.
    File? original;
    if (keepOriginal) {
      original = File(p.join(directory.path, '${newId()}-original.wav'));
      await original.writeAsBytes(
        Wav.encode(captured, sampleRate: _sampleRate),
        flush: true,
      );
    }

    _state = DictationState.idle;
    _displayLevels.clear();
    notifyListeners();

    return DictationCapture(
      file: file,
      originalFile: original,
      duration: trimmed.trimmedDuration,
      originalDuration: trimmed.originalDuration,
      storedBytes: await file.length(),
      untrimmedBytes: Wav.sizeFor(captured.length),
      sampleRate: quality.storedSampleRate,
      // Always the full-rate samples: transcription must not be penalised for
      // a storage choice.
      samples: trimmed.samples,
    );
  }

  /// Removes a stretch from the middle of a finished capture.
  ///
  /// Trimming the ends covers the throat-clear and the trailing question, but
  /// not the thing that actually happens most in a consultation room: someone
  /// interrupts, a phone rings, the clinician stops to think. Those are in the
  /// *middle*, they are obvious on a waveform, and no detector should be
  /// deciding about them.
  ///
  /// Cuts are applied one at a time against the full-rate samples, so five
  /// small cuts cost exactly what one does and none of them compounds loss.
  Future<DictationCapture> removeRange(
    DictationCapture capture, {
    required double startFraction,
    required double endFraction,
  }) async {
    final total = capture.samples.length;
    final start = (total * startFraction).round().clamp(0, total);
    final end = (total * endFraction).round().clamp(start, total);
    if (end <= start) return capture;

    final kept = Int16List(total - (end - start))
      ..setRange(0, start, capture.samples)
      ..setRange(start, total - (end - start), capture.samples, end);

    return _write(capture, kept);
  }

  /// Re-cuts a finished capture to a sub-range the clinician chose by hand.
  ///
  /// Automatic trimming is deliberately biased toward keeping audio, which
  /// means it reliably leaves things in: the throat-clear before the first
  /// word, a colleague's question at the end, the pause where someone was
  /// deciding what to say. Those are exactly the parts a person can see on a
  /// waveform and remove in a second, and no detector should be guessing at.
  ///
  /// Cuts from the full-rate samples rather than from the written file, so a
  /// second cut is not a second generation of loss.
  Future<DictationCapture> retrim(
    DictationCapture capture, {
    required double startFraction,
    required double endFraction,
  }) async {
    final total = capture.samples.length;
    final start = (total * startFraction).round().clamp(0, total);
    final end = (total * endFraction).round().clamp(start, total);
    return _write(capture, Int16List.sublistView(capture.samples, start, end));
  }

  /// Writes a new capture from edited samples, retiring the previous file.
  Future<DictationCapture> _write(
    DictationCapture previous,
    Int16List samples,
  ) async {
    final stored = quality == DictationQuality.compact
        ? Wav.downsampleByTwo(samples)
        : samples;

    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, '${newId()}.wav'));
    await file.writeAsBytes(
      Wav.encode(stored, sampleRate: quality.storedSampleRate),
      flush: true,
    );

    return DictationCapture(
      file: file,
      originalFile: previous.originalFile,
      duration: Duration(
        milliseconds: (samples.length * 1000 / _sampleRate).round(),
      ),
      originalDuration: previous.originalDuration,
      storedBytes: await file.length(),
      untrimmedBytes: previous.untrimmedBytes,
      sampleRate: quality.storedSampleRate,
      samples: samples,
    );
  }

  /// Abandons the recording. Nothing is written.
  Future<void> cancel() async {
    _ticker?.cancel();
    _ticker = null;
    await _subscription?.cancel();
    _subscription = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    _chunks.clear();
    _sampleCount = 0;
    _displayLevels.clear();
    _startedAt = null;
    _isSpeaking = false;
    _silenceSince = null;
    _state = DictationState.idle;
    notifyListeners();
  }

  Int16List _concatenate() {
    final out = Int16List(_sampleCount);
    var at = 0;
    for (final chunk in _chunks) {
      out.setRange(at, at + chunk.length, chunk);
      at += chunk.length;
    }
    return out;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }
}

/// Top-level so it can be sent to a background isolate by [compute].
VadTrimResult _trimInBackground(
  ({Int16List samples, int sampleRate}) request,
) {
  return VoiceActivityDetector(sampleRate: request.sampleRate)
      .trim(request.samples);
}
