import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 for the app-lock PIN.
///
/// The PIN gates access to the running app. It is deliberately *not* the
/// database key — see `DbKeyManager` for why the two are separated.
abstract final class PinHasher {
  /// Deliberately high for a short numeric secret: a 6-digit PIN has only
  /// 10^6 candidates, so the only defence against an offline guess of the
  /// stored hash is per-attempt cost.
  static const int iterations = 210000;
  static const int _keyLength = 32;
  static const int _saltLength = 16;

  static Uint8List randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }

  /// Returns `pbkdf2_sha256$<iterations>$<saltB64>$<hashB64>`.
  static String hash(String pin, {Uint8List? salt}) {
    final useSalt = salt ?? randomBytes(_saltLength);
    final derived = _pbkdf2(
      utf8.encode(pin),
      useSalt,
      iterations,
      _keyLength,
    );
    return 'pbkdf2_sha256\$$iterations\$'
        '${base64Encode(useSalt)}\$${base64Encode(derived)}';
  }

  static bool verify(String pin, String encoded) {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null) return false;
    final salt = base64Decode(parts[2]);
    final expected = base64Decode(parts[3]);
    final actual = _pbkdf2(
      utf8.encode(pin),
      Uint8List.fromList(salt),
      rounds,
      expected.length,
    );
    return _constantTimeEquals(actual, expected);
  }

  static Uint8List _pbkdf2(
    List<int> password,
    Uint8List salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, password);
    final blockCount = (keyLength / 32).ceil();
    final output = Uint8List(blockCount * 32);

    for (var block = 1; block <= blockCount; block++) {
      final blockIndex = Uint8List(4)
        ..[0] = (block >> 24) & 0xff
        ..[1] = (block >> 16) & 0xff
        ..[2] = (block >> 8) & 0xff
        ..[3] = block & 0xff;

      var u = Uint8List.fromList(
        hmac.convert(<int>[...salt, ...blockIndex]).bytes,
      );
      final accumulator = Uint8List.fromList(u);

      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < accumulator.length; j++) {
          accumulator[j] ^= u[j];
        }
      }
      output.setRange((block - 1) * 32, block * 32, accumulator);
    }
    return Uint8List.sublistView(output, 0, keyLength);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
