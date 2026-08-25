import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/core/security/pin_hasher.dart';

void main() {
  group('PinHasher', () {
    test('verifies a correct PIN and rejects a wrong one', () {
      final encoded = PinHasher.hash('482913');
      expect(PinHasher.verify('482913', encoded), isTrue);
      expect(PinHasher.verify('482914', encoded), isFalse);
      expect(PinHasher.verify('', encoded), isFalse);
    });

    test('salts each hash, so identical PINs do not collide on disk', () {
      final a = PinHasher.hash('123456');
      final b = PinHasher.hash('123456');
      expect(a, isNot(equals(b)));
      expect(PinHasher.verify('123456', a), isTrue);
      expect(PinHasher.verify('123456', b), isTrue);
    });

    test('encodes algorithm, iteration count, salt and hash', () {
      final parts = PinHasher.hash('999999').split(r'$');
      expect(parts, hasLength(4));
      expect(parts[0], 'pbkdf2_sha256');
      expect(int.parse(parts[1]), PinHasher.iterations);
      expect(parts[2], isNotEmpty);
      expect(parts[3], isNotEmpty);
    });

    test('rejects malformed stored values instead of throwing', () {
      expect(PinHasher.verify('123456', 'garbage'), isFalse);
      expect(PinHasher.verify('123456', r'bcrypt$1$a$b'), isFalse);
      expect(PinHasher.verify('123456', r'pbkdf2_sha256$notanumber$a$b'), isFalse);
    });

    test('uses an iteration count high enough to slow offline guessing', () {
      // A six-digit PIN has only 10^6 candidates; per-attempt cost is the only
      // defence if the stored hash is ever exfiltrated.
      expect(PinHasher.iterations, greaterThanOrEqualTo(100000));
    });

    test('generates random bytes of the requested length', () {
      final a = PinHasher.randomBytes(32);
      final b = PinHasher.randomBytes(32);
      expect(a, hasLength(32));
      expect(a, isNot(equals(b)));
    });
  });
}
