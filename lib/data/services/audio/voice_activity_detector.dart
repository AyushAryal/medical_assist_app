import 'dart:math' as math;
import 'dart:typed_data';

/// Decides which parts of a recording contain speech.
///
/// This is the "trim the silence" logic, and it is energy-based rather than
/// model-based on purpose: a clinician dictating into a phone in a clinic room
/// needs a decision every 20 ms on a device that may be six years old, and a
/// neural VAD buys accuracy that this job does not need. What matters here is
/// the failure asymmetry — **clipping a word is unacceptable, keeping half a
/// second of room tone is merely wasteful** — so every parameter below is
/// biased toward keeping audio.
///
/// The three things that make a naive energy gate unusable, and what is done
/// about each:
///
/// * **A fixed threshold does not survive two rooms.** A busy clinic sits 25 dB
///   above a quiet consulting room. So the floor is estimated continuously and
///   the gate rides above it.
/// * **Speech is not continuous.** The stop before a `t` is silence by any
///   energy measure. A gate without hangover chops words into fragments, so
///   speech keeps the gate open for [postRoll] after it stops.
/// * **The gate always opens late.** By the time energy has risen enough to
///   detect, the onset consonant is already past. So audio is held in a ring
///   buffer and [preRoll] of it is emitted retroactively.
///
/// Pure Dart, no plugin dependency — which is what lets the whole trimming
/// decision be unit-tested against synthesised audio rather than eyeballed.
class VoiceActivityDetector {
  VoiceActivityDetector({
    this.sampleRate = 16000,
    this.frameDuration = const Duration(milliseconds: 20),
    this.thresholdMarginDb = 8.0,
    this.absoluteFloorDb = -55.0,
    this.preRoll = const Duration(milliseconds: 240),
    this.postRoll = const Duration(milliseconds: 420),
    this.minSpeechRun = const Duration(milliseconds: 60),
  })  : assert(sampleRate > 0),
        assert(thresholdMarginDb > 0);

  final int sampleRate;
  final Duration frameDuration;

  /// The *widest* gap the gate will ask for, used when the recording has the
  /// dynamic range to support it. The gate adapts downward from here toward
  /// [_minimumMarginDb] as the recording's own contrast narrows.
  ///
  /// Above about 12 dB it starts dropping quiet speech at the end of
  /// sentences, which is why this is a ceiling rather than a target.
  final double thresholdMarginDb;

  /// Nothing quieter than this is ever speech, however quiet the room is.
  /// Without it, a silent recording produces a noise floor near the numerical
  /// floor and every dither bit reads as a word.
  final double absoluteFloorDb;

  /// Audio kept from *before* the gate opened, so onsets are not clipped.
  final Duration preRoll;

  /// Audio kept after the gate closes, so trailing consonants and the natural
  /// decay of a room survive.
  final Duration postRoll;

  /// How long energy must stay high before the gate opens. Rejects impulses —
  /// a door, a dropped pen, a keyboard.
  final Duration minSpeechRun;

  int get frameSamples =>
      (sampleRate * frameDuration.inMicroseconds / 1000000).round();

  int get _preRollFrames =>
      (preRoll.inMicroseconds / frameDuration.inMicroseconds).ceil();

  int get _postRollFrames =>
      (postRoll.inMicroseconds / frameDuration.inMicroseconds).ceil();

  int get _minRunFrames => math.max(
        1,
        (minSpeechRun.inMicroseconds / frameDuration.inMicroseconds).round(),
      );

  /// Splits [samples] into frames and returns, for each, whether it is kept.
  ///
  /// Exposed separately from [trim] so the decision can be tested and drawn
  /// (the live waveform in the recorder UI uses the same frame energies).
  VadAnalysis analyse(Int16List samples) {
    final frames = samples.length ~/ frameSamples;
    if (frames == 0) {
      return const VadAnalysis(
        frameDb: <double>[],
        keep: <bool>[],
        speechFrames: 0,
        noiseFloorDb: 0,
      );
    }

    final frameDb = Float64List(frames);
    for (var f = 0; f < frames; f++) {
      frameDb[f] = _dbFor(samples, f * frameSamples, frameSamples);
    }

    // ---- Noise floor -------------------------------------------------------
    //
    // Two failure modes bracket this problem, and both destroy data:
    //
    // * Track the running minimum and let the gate ride above it, and a
    //   recording with no pauses converges its own floor onto the speech.
    //   Nothing clears the threshold and the whole dictation is discarded.
    // * Compare against a fixed absolute level instead, and a loud clinic room
    //   sits above it, reads as "loud, therefore speech", and nothing is
    //   trimmed at all.
    //
    // What separates the two cases is *contrast within this recording*. A
    // window with contrast can be gated on its own statistics. A window
    // without contrast is either unbroken speech or unbroken room tone, and it
    // can only be resolved by comparison with the rest of the recording — so
    // the reference for those is the recording's own quietest tenth, and only
    // if the whole recording is flat does an absolute level get the last word.
    final sortedAll = frameDb.toList()..sort();
    final globalFloor = _percentile(sortedAll, 0.10);
    // 99th rather than the maximum, so one dropped instrument does not read as
    // the loudest thing in the recording.
    final globalPeak = _percentile(sortedAll, 0.99);
    final contrast = globalPeak - globalFloor;

    // The gate rides a *fraction of the contrast actually present*, not a
    // fixed number of decibels.
    //
    // A fixed margin assumes a quiet room, where speech sits 40 dB above the
    // floor. Automatic gain control — which every phone applies, and which
    // this app asks for elsewhere to make quiet voices audible — lifts the
    // pauses toward the speech until only a few decibels separate them. A
    // fixed 8 dB gate then finds no contrast anywhere, concludes the whole
    // recording is speech, and trims nothing. That is not a subtle failure:
    // it is the feature silently not working.
    //
    // Clamped at both ends. The floor keeps the gate above the dither on a
    // heavily compressed recording; the ceiling stops a very quiet room from
    // pushing the gate up past quiet speech at the end of a sentence.
    final margin = (contrast * 0.45).clamp(
      _minimumMarginDb,
      thresholdMarginDb,
    );
    final globallyFlat = contrast < _minimumMarginDb;

    final blocks = (frames / _blockFrames).ceil();
    final floorPerFrame = Float64List(frames);
    final thresholdPerFrame = Float64List(frames);

    if (globallyFlat) {
      // One level throughout. Loud means the clinician talked without pausing;
      // quiet means the microphone recorded an empty room.
      final isSpeech = globalPeak >= absoluteFloorDb + _flatRecordingHeadroomDb;
      final threshold = isSpeech ? globalFloor - 1 : globalPeak + 1;
      for (var f = 0; f < frames; f++) {
        floorPerFrame[f] = globalFloor;
        thresholdPerFrame[f] = threshold;
      }
    } else {
      for (var b = 0; b < blocks; b++) {
        final from = b * _blockFrames;
        final to = math.min(from + _blockFrames, frames);
        final window = frameDb.sublist(from, to)..sort();
        final localFloor = _percentile(window, 0.10);
        final localPeak = _percentile(window, 0.90);

        // A block containing both a word and the pause after it can be gated
        // on itself, which is what follows a room that gets noisier partway
        // through. A block with no internal contrast defers to the recording.
        final hasLocalContrast = localPeak - localFloor >= margin;
        final floor = hasLocalContrast
            ? math.max(localFloor, globalFloor)
            : globalFloor;

        final threshold = math.max(floor + margin, absoluteFloorDb);

        for (var f = from; f < to; f++) {
          floorPerFrame[f] = floor;
          thresholdPerFrame[f] = threshold;
        }
      }
    }

    // Voiced decision, before any padding.
    final voiced = List<bool>.filled(frames, false);
    for (var f = 0; f < frames; f++) {
      voiced[f] = frameDb[f] >= thresholdPerFrame[f];
    }

    // Require a sustained run before believing it, then pad both sides.
    final keep = List<bool>.filled(frames, false);
    var run = 0;
    for (var f = 0; f < frames; f++) {
      if (voiced[f]) {
        run++;
        if (run >= _minRunFrames) {
          // Retroactively keep the onset, including the frames that formed the
          // run before it was confirmed.
          final from = math.max(0, f - run + 1 - _preRollFrames);
          for (var k = from; k <= f; k++) {
            keep[k] = true;
          }
        }
      } else {
        if (run >= _minRunFrames) {
          final to = math.min(frames - 1, f + _postRollFrames - 1);
          for (var k = f; k <= to; k++) {
            keep[k] = true;
          }
        }
        run = 0;
      }
    }

    return VadAnalysis(
      frameDb: frameDb,
      keep: keep,
      speechFrames: keep.where((k) => k).length,
      noiseFloorDb: floorPerFrame.isEmpty ? 0 : floorPerFrame.last,
    );
  }

  /// Returns [samples] with the unspoken stretches removed.
  VadTrimResult trim(Int16List samples) {
    final analysis = analyse(samples);
    if (analysis.keep.isEmpty) {
      return VadTrimResult(
        samples: samples,
        originalSamples: samples.length,
        analysis: analysis,
        sampleRate: sampleRate,
      );
    }

    final kept = Int16List(analysis.speechFrames * frameSamples);
    var write = 0;
    for (var f = 0; f < analysis.keep.length; f++) {
      if (!analysis.keep[f]) continue;
      final start = f * frameSamples;
      kept.setRange(write, write + frameSamples, samples, start);
      write += frameSamples;
    }

    return VadTrimResult(
      samples: Int16List.sublistView(kept, 0, write),
      originalSamples: samples.length,
      analysis: analysis,
      sampleRate: sampleRate,
    );
  }

  /// The narrowest gap the gate will ride on. Below this it is measuring
  /// dither rather than the difference between a voice and a room.
  static const double _minimumMarginDb = 4.5;

  /// Frames per statistics block — one second at 20 ms frames. Long enough to
  /// contain both a word and the pause after it, short enough to follow a room
  /// that gets noisier partway through a consultation.
  ///
  /// A block that is all room tone in a recording whose room grew louder falls
  /// back to the recording-wide floor, which is now too low, so the gate lets
  /// that tone through. That is the deliberate direction to fail in: the
  /// result is a few seconds of kept silence, not a clipped word.
  static const int _blockFrames = 50;

  /// How far above the absolute floor a recording with no internal contrast at
  /// all must sit before it is read as unbroken speech rather than as an empty
  /// room. Only consulted when nothing in the recording can serve as a
  /// reference, which is the one case where an absolute judgement is the only
  /// judgement available.
  static const double _flatRecordingHeadroomDb = 12.0;

  /// Linear-interpolated percentile of an already-sorted list.
  static double _percentile(List<double> sorted, double fraction) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted.first;
    final position = fraction * (sorted.length - 1);
    final lower = position.floor();
    final upper = math.min(lower + 1, sorted.length - 1);
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  }

  /// RMS in dBFS. Full-scale sine is 0 dB; digital silence is clamped to
  /// [absoluteFloorDb] - 40 rather than negative infinity.
  double _dbFor(Int16List samples, int offset, int length) {
    var sumSquares = 0.0;
    final end = math.min(offset + length, samples.length);
    for (var i = offset; i < end; i++) {
      final normalised = samples[i] / 32768.0;
      sumSquares += normalised * normalised;
    }
    final count = end - offset;
    if (count == 0) return absoluteFloorDb - 40;
    final rms = math.sqrt(sumSquares / count);
    if (rms <= 1e-9) return absoluteFloorDb - 40;
    return 20 * math.log(rms) / math.ln10;
  }
}

/// Per-frame output of the detector, reused by the live waveform display.
class VadAnalysis {
  const VadAnalysis({
    required this.frameDb,
    required this.keep,
    required this.speechFrames,
    required this.noiseFloorDb,
  });

  /// Energy of each frame, in dBFS.
  final List<double> frameDb;

  /// Whether each frame survives trimming, padding included.
  final List<bool> keep;

  final int speechFrames;

  /// The floor the gate settled on — shown in the UI so an operator can tell a
  /// noisy room from a broken microphone.
  final double noiseFloorDb;

  int get totalFrames => keep.length;

  double get speechFraction => totalFrames == 0 ? 0 : speechFrames / totalFrames;
}

class VadTrimResult {
  const VadTrimResult({
    required this.samples,
    required this.originalSamples,
    required this.analysis,
    required this.sampleRate,
  });

  /// Speech only, with onsets and decays preserved.
  final Int16List samples;
  final int originalSamples;
  final VadAnalysis analysis;
  final int sampleRate;

  Duration get originalDuration => Duration(
        milliseconds: (originalSamples * 1000 / sampleRate).round(),
      );

  Duration get trimmedDuration => Duration(
        milliseconds: (samples.length * 1000 / sampleRate).round(),
      );

  Duration get removed => originalDuration - trimmedDuration;

  /// Proportion of the recording that was silence, 0–1.
  double get removedFraction =>
      originalSamples == 0 ? 0 : 1 - (samples.length / originalSamples);

  /// True when trimming achieved little — worth saying so rather than
  /// reporting "0% saved" as though something went wrong. A continuous
  /// dictation with no pauses is a *good* recording.
  bool get negligible => removedFraction < 0.05;
}
