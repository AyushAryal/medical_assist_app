import 'package:opt_kit/opt_kit.dart' show DraftStore;

import 'app_meta_store.dart';

/// The app's implementation of the kit's [DraftStore]: draft snapshots live
/// in the `app_meta` key/value table *inside* the encrypted SQLCipher
/// database, under a `draft:` prefix.
///
/// Why here and not SharedPreferences or a plist: a half-typed medication or
/// allergy is patient data, and the app's data-at-rest policy is that patient
/// data lives only behind the database key. The store also inherits
/// `AppMetaStore`'s lock behaviour for free — once the database is closed on
/// lock, every call is a silent no-op, so a draft can never be written (or
/// read) past the lock screen.
class MetaDraftStore implements DraftStore {
  const MetaDraftStore(this._meta);

  final MetaKeyValue _meta;

  static const String _prefix = 'draft:';

  @override
  Future<String?> read(String key) => _meta.read('$_prefix$key');

  @override
  Future<void> write(String key, String json) =>
      _meta.write('$_prefix$key', json);

  @override
  Future<void> delete(String key) => _meta.delete('$_prefix$key');
}
