import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'agentic/agentic_module.dart';
import 'app.dart';
import 'core/app_bootstrap.dart';
import 'core/modules/entitlements.dart';
import 'core/security/app_lock_service.dart';
import 'core/security/secure_store.dart';
import 'core/theme/theme_config.dart';
import 'core/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Both orientations: phones are used portrait one-handed, tablets landscape
  // on a desk or trolley.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Appearance comes from a token file, never from literals in widget code.
  final themeConfig = await ThemeConfig.load();

  final secureStore = SecureStore.platformDefault();
  final lockService = AppLockService(secureStore);
  await lockService.initialise();

  final entitlements = Entitlements();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>(
          create: (_) => ThemeController(themeConfig),
        ),
        ChangeNotifierProvider<AppLockService>.value(value: lockService),
        ChangeNotifierProvider<Entitlements>.value(value: entitlements),
        ChangeNotifierProvider<AppBootstrap>(
          create: (_) => AppBootstrap(
            secureStore: secureStore,
            lockService: lockService,
            entitlements: entitlements,
          ),
        ),
      ],
      // The one place the app references the agentic module. Delete
      // `lib/agentic/` and change this to `const MedicalApp()` (agentHost null)
      // and the app builds and runs with no agent affordances.
      child: const MedicalApp(agentHost: AgentModuleHost()),
    ),
  );
}
