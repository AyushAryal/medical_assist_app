import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:opt_kit/opt_kit.dart' show OptUnfocus;
import 'package:provider/provider.dart';

import 'features/assist/assist.dart';

import 'core/agentic/agent_host.dart';
import 'core/agentic/agent_scope.dart';
import 'core/app_bootstrap.dart';
import 'core/branding/splash_gate.dart';
import 'core/routing/app_router.dart';
import 'core/security/app_lock_service.dart';
import 'core/modules/workflow_preferences.dart';
import 'core/session/session_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/theme/theme_scope.dart';
import 'core/widgets/glass.dart';
import 'data/repositories/clinical_repository.dart';
import 'features/lock/lock.dart';

class MedicalApp extends StatefulWidget {
  const MedicalApp({super.key, this.agentHost});

  /// The agentic module's host, injected at the composition root. Null when
  /// the module is not installed — the app then runs with no agent affordances
  /// and never references anything under `lib/agentic/`.
  final AgentHost? agentHost;

  @override
  State<MedicalApp> createState() => _MedicalAppState();
}

class _MedicalAppState extends State<MedicalApp> with WidgetsBindingObserver {
  final GoRouter _router = AppRouter.build();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Auto-lock on backgrounding. A device left face-up on a desk between
  /// patients is the most common way a chart gets seen by the wrong person.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = context.read<AppLockService>();
    final now = DateTime.now();

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        lock.onBackgrounded(now);
      case AppLifecycleState.resumed:
        lock.onResumed(now);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final config = themeController.config;

    return ThemeScope(
      config: config,
      brightness: MediaQuery.platformBrightnessOf(context),
      child: MaterialApp.router(
        title: 'Clinical Records',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(config, Brightness.light),
        darkTheme: AppTheme.build(config, Brightness.dark),
        themeMode: themeController.mode,
        routerConfig: _router,
        // The ambient wash sits at the very root so every route — shell tabs
        // and full-screen charts alike — has the same ground beneath it.
        // Without it the translucent panels would have nothing to sample.
        // The branded launch splash sits at the very top on cold start: it
        // paints over the ambient wash + lock gate for a minimum beat (so the
        // "an OptERP product" credit is seen) while unlock and the database
        // open proceed underneath, then fades out to reveal the lock gate.
        // OptUnfocus: tapping anywhere non-interactive dismisses the keyboard
        // so form footers are never stranded behind the IME.
        builder: (context, child) => OptUnfocus(
          child: SplashGate(
            child: AmbientBackground(
              child: LockGate(
                child: _DataScope(
                  child: AgentScope(
                    host: widget.agentHost,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Republishes the post-unlock services as providers.
///
/// They cannot be created in `main()` because they do not exist until the
/// database is opened, and they must disappear again when the app re-locks.
class _DataScope extends StatelessWidget {
  const _DataScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bootstrap = context.watch<AppBootstrap>();
    if (!bootstrap.isReady) return child;

    // AppBootstrap is deliberately not re-provided here. It is already exposed
    // by the ChangeNotifierProvider in main.dart, which sits above
    // MaterialApp and therefore above this builder — so descendants reach it
    // anyway. Re-declaring it as a plain Provider would also throw, because
    // Provider rejects Listenable subtypes it cannot propagate updates for.
    return MultiProvider(
      providers: [
        Provider<ClinicalRepository>.value(value: bootstrap.repository),
        ChangeNotifierProvider<SessionController>.value(
          value: bootstrap.session,
        ),
        ChangeNotifierProvider<WorkflowPreferences>.value(
          value: bootstrap.workflows,
        ),
      ],
      // Wrapped here rather than in the shell so the assistant is genuinely
      // on every screen — a chart, a note and a settings page are all pushed
      // above the shell and would otherwise lose it.
      child: _ThemePreferenceSync(
        child: FloatingAssistant(child: child),
      ),
    );
  }
}

/// Applies the stored light/dark preference once the database is open.
///
/// [ThemeController] is built in `main()`, before the encrypted database
/// exists, so it cannot read the saved preference at construction. The value
/// lives in `app_meta` inside the encrypted database — deliberately, since it
/// is per-clinician state — which means it can only be restored here, after
/// unlock. Without this the preference silently resets on every launch.
class _ThemePreferenceSync extends StatefulWidget {
  const _ThemePreferenceSync({required this.child});

  final Widget child;

  @override
  State<_ThemePreferenceSync> createState() => _ThemePreferenceSyncState();
}

class _ThemePreferenceSyncState extends State<_ThemePreferenceSync> {
  bool _applied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_applied) return;
    _applied = true;

    final stored = context.read<SessionController>().themeMode;
    final controller = context.read<ThemeController>();
    if (controller.mode != stored) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.setMode(stored);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
