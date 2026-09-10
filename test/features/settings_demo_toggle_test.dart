import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/core/app_bootstrap.dart';
import 'package:medical_app/core/audit/audit_service.dart';
import 'package:medical_app/core/db/app_database.dart';
import 'package:medical_app/core/db/app_meta_store.dart';
import 'package:medical_app/core/db/schema.dart';
import 'package:medical_app/core/design/design.dart';
import 'package:medical_app/core/modules/entitlements.dart';
import 'package:medical_app/core/security/app_lock_service.dart';
import 'package:medical_app/core/security/secure_store.dart';
import 'package:medical_app/core/session/session_controller.dart';
import 'package:medical_app/core/theme/theme_config.dart';
import 'package:medical_app/core/theme/theme_controller.dart';
import 'package:medical_app/data/repositories/clinical_repository.dart';
import 'package:medical_app/features/settings/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The demo-data toggle has vanished from Settings more than once, and each
/// time the report was "the toggle disappeared" with no record of which build
/// was being looked at. The rule it guards: `demoDataAllowed` is true in every
/// debug build (and `flutter test` runs in debug), so the section must exist
/// here. A release build without --dart-define=ALLOW_DEMO_DATA=true compiles
/// it out on purpose — that case is policy, not a bug, and is documented in
/// RELEASE.md.
void main() {
  final ThemeConfig config = ThemeConfig.fromJson(<String, dynamic>{
    'id': 'test',
    'name': 'Test',
    'typography': <String, dynamic>{},
    'metrics': <String, dynamic>{},
    'light': <String, dynamic>{},
    'dark': <String, dynamic>{},
  });

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: Schema.version,
        onCreate: (db, version) async {
          for (final step in Schema.migrations) {
            for (final statement in step) {
              await db.execute(statement);
            }
          }
        },
      ),
    );
  });

  tearDown(() async => db.close());

  testWidgets('debug builds keep the demo-data toggle in Settings',
      (tester) async {
    final database = AppDatabase.withHandle(db);
    final repository = ClinicalRepository.wire(
      database: database,
      audit: AuditService(database),
    );
    final meta = AppMetaStore(database);
    final session = SessionController(repository, meta);
    final store = _MemorySecureStore();
    final lock = AppLockService(store);
    final bootstrap = AppBootstrap(
      secureStore: store,
      lockService: lock,
      entitlements: Entitlements(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionController>.value(value: session),
          ChangeNotifierProvider<AppLockService>.value(value: lock),
          ChangeNotifierProvider<AppBootstrap>.value(value: bootstrap),
          ChangeNotifierProvider<ThemeController>(
            create: (_) => ThemeController(config),
          ),
          Provider<ClinicalRepository>.value(value: repository),
        ],
        child: ThemeScope(
          config: config,
          brightness: Brightness.light,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.text('Load demo data');
    await tester.scrollUntilVisible(
      toggle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(toggle, findsOneWidget);
  });
}

/// In-memory stand-in for the platform keychain, which has no implementation
/// under `flutter test`.
class _MemorySecureStore extends SecureStore {
  _MemorySecureStore() : super(const FlutterSecureStorage());

  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<bool> contains(String key) async => _values.containsKey(key);

  @override
  Future<void> wipe() async => _values.clear();
}
