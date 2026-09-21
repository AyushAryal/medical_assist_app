import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../../core/security/app_lock_service.dart';
import 'lock_screen.dart';
import 'pin_setup_screen.dart';

/// Stands between the router and every screen behind it.
///
/// Nothing below this widget can render until the app is unlocked *and* the
/// encrypted database is open, so there is no code path where a chart paints
/// before authentication.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockService>();
    final bootstrap = context.watch<AppBootstrap>();

    final (String state, Widget body) = _resolve(lock, bootstrap);

    // Unlock is the most-travelled moment in the app; a hard cut between the
    // PIN pad, the opening wait and the dashboard reads as three unrelated
    // apps. One gentle cross-fade with a breath of scale ties them together.
    // Everything is painted on the shared ambient background, so the fade
    // blends surfaces rather than flashing them.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey<String>(state), child: body),
    );
  }

  (String, Widget) _resolve(AppLockService lock, AppBootstrap bootstrap) {
    // First run: no PIN has ever been set.
    if (lock.state == AppLockState.uninitialised) {
      return ('setup', const PinSetupScreen(isFirstRun: true));
    }

    if (lock.state == AppLockState.locked) {
      // Drop the decrypted handle the moment we return to the lock screen.
      if (bootstrap.phase != BootstrapPhase.idle) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          bootstrap.closeOnLock();
        });
      }
      return ('locked', const LockScreen());
    }

    // Unlocked but the database has not been opened yet.
    if (!bootstrap.isReady) {
      if (bootstrap.phase == BootstrapPhase.idle) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          bootstrap.openAfterUnlock();
        });
      }
      return ('opening', _BootstrapStatus(bootstrap: bootstrap));
    }

    return ('ready', widget.child);
  }
}

class _BootstrapStatus extends StatelessWidget {
  const _BootstrapStatus({required this.bootstrap});

  final AppBootstrap bootstrap;

  @override
  Widget build(BuildContext context) {
    if (bootstrap.phase == BootstrapPhase.failed) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Could not open the clinical database',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '${bootstrap.error}',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: bootstrap.openAfterUnlock,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const LoadingState(message: 'Opening the encrypted record…');
  }
}
