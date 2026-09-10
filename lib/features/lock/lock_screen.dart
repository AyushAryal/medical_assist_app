import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/security/app_lock_service.dart';
import 'lock_layout.dart';
import 'pin_pad.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const int _pinLength = 6;

  String _entry = '';
  String? _message;
  bool _hasError = false;
  bool _busy = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  /// Offered automatically on arrival: the fastest unlock is the one the user
  /// never had to ask for.
  Future<void> _tryBiometrics({bool userInitiated = false}) async {
    final lock = context.read<AppLockService>();
    final available =
        await lock.canUseBiometrics() && await lock.isBiometricEnabled();

    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (!available) return;
    if (!userInitiated && lock.failedAttempts > 0) return;

    final failure = await lock.unlockWithBiometrics();
    if (!mounted || failure == null) return;

    if (userInitiated) {
      setState(() => _message = _describe(failure, lock));
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);

    final lock = context.read<AppLockService>();
    final failure = await lock.unlockWithPin(_entry);

    if (!mounted) return;
    if (failure == null) {
      setState(() {
        _busy = false;
        _entry = '';
        _hasError = false;
        _message = null;
      });
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _entry = '';
      _hasError = true;
      _message = _describe(failure, lock);
    });
  }

  String _describe(UnlockFailure failure, AppLockService lock) =>
      switch (failure) {
        UnlockFailure.wrongPin => lock.remainingAttempts <= 3
            ? 'Incorrect PIN. ${lock.remainingAttempts} attempts remaining.'
            : 'Incorrect PIN.',
        UnlockFailure.throttled =>
          'Too many failed attempts. Restart the app to try again.',
        UnlockFailure.biometricUnavailable => 'Biometrics unavailable.',
        UnlockFailure.biometricFailed => 'Biometric check did not match.',
      };

  void _onDigit(String digit) {
    if (_entry.length >= _pinLength || _busy) return;
    setState(() {
      _entry += digit;
      _hasError = false;
      _message = null;
    });
    if (_entry.length == _pinLength) _submit();
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() {
      _entry = _entry.substring(0, _entry.length - 1);
      _hasError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockService>();
    final palette = context.palette;
    final m = context.metrics;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LockLayout(
        header: Column(
          children: <Widget>[
            Icon(
              Icons.lock_outline,
              size: 44,
              color: palette.primary,
            ),
            SizedBox(height: m.spaceLg),
            Text('Clinical Records', style: context.texts.headlineSmall),
            SizedBox(height: m.spaceXs),
            Text(
              'Patient data is encrypted on this device.',
              style: context.texts.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        progress: Column(
          children: <Widget>[
            PinDots(
              length: _pinLength,
              filled: _entry.length,
              hasError: _hasError,
            ),
            SizedBox(height: m.spaceLg),
            SizedBox(
              height: 40,
              child: _message == null
                  ? null
                  : Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: context.texts.bodySmall?.copyWith(
                        color: _hasError || lock.isThrottled
                            ? palette.critical
                            : palette.onSurfaceMuted,
                      ),
                    ),
            ),
          ],
        ),
        keypad: PinPad(
          enabled: !_busy && !lock.isThrottled,
          onDigit: _onDigit,
          onBackspace: _onBackspace,
          onBiometric: _biometricAvailable
              ? () => _tryBiometrics(userInitiated: true)
              : null,
        ),
      ),
    );
  }
}
