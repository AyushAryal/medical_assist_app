import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/data/services/audio/wav.dart';

void main() {
  group('Wav', () {
    test('round-trips samples, rate and channel count', () {
      final samples = Int16List.fromList(<int>[0, 1, -1, 32767, -32768, 500]);
      final bytes = Wav.encode(samples, sampleRate: 16000);

      final decoded = Wav.decode(bytes);

      expect(decoded.samples, samples);
      expect(decoded.sampleRate, 16000);
      expect(decoded.channels, 1);
    });

    test('writes a header a decoder can find its way around', () {
      final bytes = Wav.encode(Int16List(160), sampleRate: 16000);

      expect(String.fromCharCodes(bytes, 0, 4), 'RIFF');
      expect(String.fromCharCodes(bytes, 8, 12), 'WAVE');
      expect(String.fromCharCodes(bytes, 36, 40), 'data');
      expect(bytes.length, Wav.sizeFor(160));

      final data = ByteData.sublistView(bytes);
      // Declared RIFF size excludes the first eight bytes.
      expect(data.getUint32(4, Endian.little), bytes.length - 8);
      expect(data.getUint32(24, Endian.little), 16000); // sample rate
      expect(data.getUint32(28, Endian.little), 32000); // byte rate, mono 16bit
      expect(data.getUint16(34, Endian.little), 16); // bits per sample
    });

    test('reports duration from rate rather than assuming one', () {
      final oneSecond = Wav.decode(
        Wav.encode(Int16List(8000), sampleRate: 8000),
      );
      expect(oneSecond.duration.inMilliseconds, 1000);
    });

    test('tolerates a trailing odd byte from a split stream event', () {
      // A recorder callback can split a 16-bit sample across two events. The
      // orphan byte must be dropped, not absorbed — absorbing it shifts every
      // later sample by one byte and turns the recording into noise.
      final bytes = Uint8List.fromList(<int>[0x10, 0x00, 0x20, 0x00, 0x30]);
      final samples = Wav.pcm16FromBytes(bytes);

      expect(samples, Int16List.fromList(<int>[0x10, 0x20]));
    });

    test('rejects a non-PCM file rather than decoding it as noise', () {
      final bytes = Wav.encode(Int16List(10), sampleRate: 16000);
      // Rewrite the format tag as IEEE float.
      ByteData.sublistView(bytes).setUint16(20, 3, Endian.little);

      expect(() => Wav.decode(bytes), throwsA(isA<FormatException>()));
    });

    test('rejects something that is not a WAV at all', () {
      expect(
        () => Wav.decode(Uint8List.fromList('not audio at all'.codeUnits)),
        throwsA(isA<FormatException>()),
      );
    });

    test('downsampling by two averages rather than dropping samples', () {
      // Dropping alternate samples aliases everything above the new Nyquist
      // back into the speech band; averaging is the cheapest filter that does
      // not. A full-scale alternating signal is the worst case: it is exactly
      // at Nyquist, and must average to silence rather than to a DC offset.
      final nyquist = Int16List.fromList(
        List<int>.generate(16, (i) => i.isEven ? 20000 : -20000),
      );

      final halved = Wav.downsampleByTwo(nyquist);

      expect(halved.length, 8);
      expect(halved.every((s) => s == 0), isTrue);
    });

    test('downsampling preserves a signal well below the new Nyquist', () {
      final steady = Int16List.fromList(List<int>.filled(16, 1000));
      expect(Wav.downsampleByTwo(steady), everyElement(1000));
    });
  });
}
