import 'dart:math' as math;
import 'dart:typed_data';

/// Minimal WAV reading and writing, plus the one resample the app needs.
///
/// WAV rather than a compressed format because two consumers pull in opposite
/// directions: speech recognition wants uncompressed 16 kHz mono PCM, and the
/// stored attachment has to be playable by the platform audio stack years
/// later. Linear PCM in a RIFF container is the only format that satisfies
/// both without a codec dependency, and it is the format every decoder on
/// every platform has supported for thirty years.
///
/// The cost is size, which is why silence trimming and the optional downsample
/// to 8 kHz exist rather than being niceties.
abstract final class Wav {
  static const int _headerBytes = 44;
  static const int _pcmFormat = 1;

  /// Wraps 16-bit PCM in a RIFF/WAVE container.
  static Uint8List encode(
    Int16List samples, {
    required int sampleRate,
    int channels = 1,
  }) {
    final dataBytes = samples.length * 2;
    final out = ByteData(_headerBytes + dataBytes);

    void ascii(int offset, String tag) {
      for (var i = 0; i < tag.length; i++) {
        out.setUint8(offset + i, tag.codeUnitAt(i));
      }
    }

    final byteRate = sampleRate * channels * 2;

    ascii(0, 'RIFF');
    out.setUint32(4, 36 + dataBytes, Endian.little); // size after this field
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    out.setUint32(16, 16, Endian.little); // fmt chunk size
    out.setUint16(20, _pcmFormat, Endian.little);
    out.setUint16(22, channels, Endian.little);
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, byteRate, Endian.little);
    out.setUint16(32, channels * 2, Endian.little); // block align
    out.setUint16(34, 16, Endian.little); // bits per sample
    ascii(36, 'data');
    out.setUint32(40, dataBytes, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      out.setInt16(_headerBytes + i * 2, samples[i], Endian.little);
    }

    return out.buffer.asUint8List();
  }

  /// Reads the sample rate and PCM payload of a WAV produced by [encode].
  ///
  /// Deliberately not a general WAVE parser: it walks the chunk list to find
  /// `fmt ` and `data` rather than assuming a 44-byte header, because some
  /// platforms insert a `LIST` chunk, but it rejects anything that is not
  /// 16-bit linear PCM instead of guessing.
  static WavData decode(Uint8List bytes) {
    if (bytes.length < 12) throw const FormatException('Not a WAV file');
    final data = ByteData.sublistView(bytes);

    String tag(int offset) => String.fromCharCodes(bytes, offset, offset + 4);

    if (tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE file');
    }

    var offset = 12;
    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    Int16List? samples;

    while (offset + 8 <= bytes.length) {
      final id = tag(offset);
      final size = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;

      if (id == 'fmt ' && body + 16 <= bytes.length) {
        final format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bitsPerSample = data.getUint16(body + 14, Endian.little);
        if (format != _pcmFormat) {
          throw FormatException('Only linear PCM is supported (format $format)');
        }
      } else if (id == 'data') {
        final available = math.min(size, bytes.length - body);
        final count = available ~/ 2;
        final out = Int16List(count);
        for (var i = 0; i < count; i++) {
          out[i] = data.getInt16(body + i * 2, Endian.little);
        }
        samples = out;
      }

      // Chunks are word-aligned: an odd size is followed by a pad byte.
      offset = body + size + (size.isOdd ? 1 : 0);
    }

    if (sampleRate == null || samples == null) {
      throw const FormatException('WAV file has no fmt or data chunk');
    }
    if (bitsPerSample != 16) {
      throw FormatException('Only 16-bit PCM is supported (got $bitsPerSample)');
    }

    return WavData(
      samples: samples,
      sampleRate: sampleRate,
      channels: channels ?? 1,
    );
  }

  /// Interprets a little-endian byte buffer from the recorder as 16-bit PCM.
  static Int16List pcm16FromBytes(Uint8List bytes) {
    // An odd length means a frame was split across two stream events; drop the
    // orphan byte rather than shifting every subsequent sample by one and
    // turning the whole recording into noise.
    final usable = bytes.length - (bytes.length % 2);
    final data = ByteData.sublistView(bytes, 0, usable);
    final out = Int16List(usable ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt16(i * 2, Endian.little);
    }
    return out;
  }

  /// Halves the sample rate, for storing a dictation at telephone quality once
  /// it has been transcribed at full rate.
  ///
  /// Averaging pairs of samples is a 2-tap box filter — crude as a filter, but
  /// it is an *anti-aliasing* filter, which is the part that matters. Naive
  /// sample-dropping folds everything above 4 kHz back down into the speech
  /// band as intermodulation, and the result sounds broken rather than merely
  /// dull.
  static Int16List downsampleByTwo(Int16List samples) {
    final out = Int16List(samples.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = ((samples[i * 2] + samples[i * 2 + 1]) / 2).round();
    }
    return out;
  }

  /// Bytes a WAV of this many samples will occupy on disk.
  static int sizeFor(int sampleCount) => _headerBytes + sampleCount * 2;
}

class WavData {
  const WavData({
    required this.samples,
    required this.sampleRate,
    required this.channels,
  });

  final Int16List samples;
  final int sampleRate;
  final int channels;

  Duration get duration => Duration(
        milliseconds: (samples.length * 1000 / (sampleRate * channels)).round(),
      );
}
