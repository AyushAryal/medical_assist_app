import 'dart:convert';

import 'pin_hasher.dart';
import 'secure_store.dart';

/// Owns the SQLCipher passphrase (the database encryption key, "DEK").
///
/// Design notes, because this is the part that matters most:
///
/// * The DEK is 32 random bytes generated on device at first launch. It is
///   never derived from the PIN and never leaves the device.
/// * It is held in the platform keystore, so the OS — not this app — enforces
///   that no other application can read it. That is what satisfies "only the
///   application can decrypt the database".
/// * The PIN is intentionally a *separate* secret that gates the UI. If the
///   DEK were derived from the PIN, a forgotten PIN would mean permanent,
///   unrecoverable loss of every patient record on the device.
///
/// Planned hardening (see SystemArchitecture.md § Key management roadmap):
/// wrap the DEK with a KEK derived from the PIN so the ciphertext is useless
/// even to an attacker who defeats the keystore, and add an operator-held
/// recovery wrap so a forgotten PIN is recoverable rather than fatal.
class DbKeyManager {
  const DbKeyManager(this._store);

  final SecureStore _store;

  static const String _dekKey = 'db.dek.v1';
  static const int _dekLengthBytes = 32;

  /// Returns the existing DEK, generating and persisting one on first run.
  Future<String> obtainKey() async {
    final existing = await _store.read(_dekKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = base64UrlEncode(PinHasher.randomBytes(_dekLengthBytes));
    await _store.write(_dekKey, generated);
    return generated;
  }

  Future<bool> hasKey() => _store.contains(_dekKey);

  /// Destroys the key. The encrypted database file becomes permanently
  /// unreadable — this is the "remote wipe" / "lost device" primitive, not a
  /// logout.
  Future<void> destroyKey() => _store.delete(_dekKey);
}
