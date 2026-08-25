import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/data/services/audio/voice_activity_detector.dart';

/// Synthesises audio rather than shipping fixture files, so the assertions
/// state the acoustic condition being tested instead of pointing at a blob.
///
/// The bias under test throughout is deliberate: the detector must never clip
/// speech, and may keep some silence.
void main() {
  const rate = 16000;

  Int16List tone({
    required Duration length,
    double amplitude = 0.3,
    double frequency = 220,
  }) {
    final count = (rate * length.inMilliseconds / 1000).round();
    final out = Int16List(count);
    for (var i = 0; i < count; i++) {
      out[i] = (math.sin(2 * math.pi * frequency * i / rate) *
              amplitude *
              32767)
          .round();
    }
    return out;
  }

  Int16List noise({required Duration length, double amplitude = 0.002}) {
    final count = (rate * length.inMilliseconds / 1000).round();
    final random = math.Random(7);
    final out = Int16List(count);
    for (var i = 0; i < count; i++) {
      out[i] = ((random.nextDouble() * 2 - 1) * amplitude * 32767).round();
    }
    return out;
  }

  Int16List concat(List<Int16List> parts) {
    final total = parts.fold<int>(0, (sum, p) => sum + p.length);
    final out = Int16List(total);
    var at = 0;
    for (final part in parts) {
      out.setRange(at, at + part.length, part);
      at += part.length;
    }
    return out;
  }

  group('VoiceActivityDetector', () {
    test('removes a long silence between two utterances', () {
      final detector = VoiceActivityDetector(sampleRate: rate);
      final audio = concat(<Int16List>[
        tone(length: const Duration(seconds: 1)),
        noise(length: const Duration(seconds: 4)),
        tone(length: const Duration(seconds: 1)),
      ]);

      final result = detector.trim(audio);

      expect(result.originalDuration.inSeconds, 6);
      // Both utterances survive, plus pre/post-roll padding around each.
      expect(
        result.trimmedDuration.inMilliseconds,
        greaterThanOrEqualTo(2000),
        reason: 'neither utterance may be clipped',
      );
      expect(
        result.trimmedDuration.inMilliseconds,
        lessThan(3600),
        reason: 'most of the 4s gap should be gone',
      );
      expect(result.removedFraction, greaterThan(0.4));
      expect(result.negligible, isFalse);
    });

    test('keeps continuous speech essentially untouched', () {
      final detector = VoiceActivityDetector(sampleRate: rate);
      final result = detector.trim(tone(length: const Duration(seconds: 3)));

      expect(result.removedFraction, lessThan(0.05));
      expect(result.negligible, isTrue);
    });

    test('a recording that is only room tone trims to almost nothing', () {
      final detector = VoiceActivityDetector(sampleRate: rate);
      final result = detector.trim(noise(length: const Duration(seconds: 5)));

      expect(
        result.trimmedDuration.inMilliseconds,
        lessThan(600),
        reason: 'silence must not survive as speech',
      );
    });

    test('digital silence is never mistaken for speech', () {
      final detector = VoiceActivityDetector(sampleRate: rate);
      final result = detector.trim(Int16List(rate * 3));

      expect(result.samples.length, 0);
    });

    test('an impulse shorter than minSpeechRun is rejected', () {
      final detector = VoiceActivityDetector(sampleRate: rate);
      final audio = concat(<Int16List>[
        noise(length: const Duration(seconds: 2)),
        // 10 ms click — below the 60 ms sustained-run requirement.
        tone(length: const Duration(milliseconds: 10), amplitude: 0.8),
        noise(length: const Duration(seconds: 2)),
      ]);

      final result = detector.trim(audio);

      expect(
        result.trimmedDuration.inMilliseconds,
        lessThan(500),
        reason: 'a dropped pen is not dictation',
      );
    });

    test('speech onset is not clipped — pre-roll is emitted retroactively', () {
      final detector = VoiceActivityDetector(
        sampleRate: rate,
        preRoll: const Duration(milliseconds: 240),
      );
      final audio = concat(<Int16List>[
        noise(length: const Duration(seconds: 2)),
        tone(length: const Duration(milliseconds: 500)),
      ]);

      final analysis = detector.analyse(audio);
      final firstKept = analysis.keep.indexOf(true);
      final speechStartFrame =
          (2000 / detector.frameDuration.inMilliseconds).round();

      expect(firstKept, lessThan(speechStartFrame));
      expect(
        speechStartFrame - firstKept,
        greaterThanOrEqualTo(6),
        reason: '240ms of pre-roll is 12 frames at 20ms; allow for the '
            'confirmation run',
      );
    });

    test('adapts to a noisy room instead of keeping everything', () {
      final detector = VoiceActivityDetector(sampleRate: rate);
      // Room tone 25 dB louder than the quiet case, speech above it.
      final loudRoom = noise(length: const Duration(seconds: 3), amplitude: 0.03);
      final audio = concat(<Int16List>[
        loudRoom,
        tone(length: const Duration(seconds: 1), amplitude: 0.4),
        loudRoom,
      ]);

      final result = detector.trim(audio);

      expect(
        result.removedFraction,
        greaterThan(0.3),
        reason: 'a loud room must not defeat the gate',
      );
      expect(
        result.trimmedDuration.inMilliseconds,
        greaterThanOrEqualTo(1000),
        reason: 'the utterance itself must survive intact',
      );
    });

    test('trims speech that a compressor has flattened', () {
      // What automatic gain control does to a recording: it lifts the quiet
      // passages toward the loud ones, so the gap between speech and room tone
      // narrows to a few decibels. A detector tuned for a wide gap sees no
      // contrast, concludes the whole thing is speech, and trims nothing —
      // which is what "the trimming does not do anything" looks like in
      // practice.
      final detector = VoiceActivityDetector(sampleRate: rate);
      final audio = concat(<Int16List>[
        tone(length: const Duration(seconds: 1), amplitude: 0.30),
        // Only about 7 dB below the speech, not 45.
        noise(length: const Duration(seconds: 4), amplitude: 0.20),
        tone(length: const Duration(seconds: 1), amplitude: 0.30),
      ]);

      final result = detector.trim(audio);

      expect(
        result.removedFraction,
        greaterThan(0.35),
        reason: 'a compressed recording must still trim',
      );
      expect(
        result.trimmedDuration.inMilliseconds,
        greaterThanOrEqualTo(2000),
        reason: 'and must not clip either utterance',
      );
    });

    test('frame energies are reported for the live waveform', () {
      final detector = VoiceActivityDetector(sampleRate: rate);
      final analysis = detector.analyse(tone(length: const Duration(seconds: 1)));

      expect(analysis.frameDb.length, 50); // 1s / 20ms
      expect(analysis.keep.length, 50);
      expect(analysis.speechFraction, greaterThan(0.9));
      // A 0.3-amplitude sine is about -13 dBFS RMS.
      expect(analysis.frameDb.first, closeTo(-13.5, 2));
    });
  });
}
