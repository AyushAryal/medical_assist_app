import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper over the platform keystore/keychain.
///
/// Android wraps each value with an Android Keystore-held key (AES-GCM under
/// an RSA-OAEP wrap) — the plugin's default since v11, so no cipher options
/// are set here. iOS uses the Keychain with `first_unlock_this_device`, which
/// keeps entries off encrypted backups and off any other device while still
/// allowing background work after the first unlock following a reboot.
class SecureStore {
  const SecureStore(this._storage);

  final FlutterSecureStorage _storage;

  factory SecureStore.platformDefault() => const SecureStore(
        FlutterSecureStorage(
          aOptions: AndroidOptions(resetOnError: false),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        ),
      );

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<bool> contains(String key) => _storage.containsKey(key: key);

  /// Wipes every secret this app owns. Because the database key lives here,
  /// this permanently renders the encrypted database unreadable — callers must
  /// treat it as a destructive operation and confirm with the user first.
  Future<void> wipe() => _storage.deleteAll();
}
