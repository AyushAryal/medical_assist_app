import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'pin_hasher.dart';
import 'secure_store.dart';

enum AppLockState { uninitialised, locked, unlocked }

enum UnlockFailure { wrongPin, biometricUnavailable, biometricFailed, throttled }

/// Gates access to decrypted PHI behind biometrics with a PIN fallback.
///
/// A PIN is always required to be set — biometrics can be unenrolled, fail in
/// gloves, or be unavailable on the device, and a clinician must never be
/// locked out of a patient record mid-consultation.
class AppLockService extends ChangeNotifier {
  AppLockService(this._store, {LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final SecureStore _store;
  final LocalAuthentication _localAuth;

  static const String _pinKey = 'lock.pin.v1';
  static const String _biometricEnabledKey = 'lock.biometric.enabled';
  static const String _failedAttemptsKey = 'lock.failed.count';

  /// After this many wrong PINs the app refuses further attempts until it is
  /// restarted. Kept generous enough not to punish a fat-fingered clinician,
  /// tight enough to make online guessing impractical.
  static const int maxFailedAttempts = 8;

  /// Re-lock after this long in the background. Short by consumer-app
  /// standards, because an unattended unlocked device in a clinic is an
  /// unattended patient chart.
  static const Duration backgroundLockTimeout = Duration(minutes: 2);

  AppLockState _state = AppLockState.uninitialised;
  int _failedAttempts = 0;
  DateTime? _backgroundedAt;

  AppLockState get state => _state;
  int get failedAttempts => _failedAttempts;
  int get remainingAttempts => maxFailedAttempts - _failedAttempts;
  bool get isThrottled => _failedAttempts >= maxFailedAttempts;
  bool get isUnlocked => _state == AppLockState.unlocked;

  Future<void> initialise() async {
    _failedAttempts =
        int.tryParse(await _store.read(_failedAttemptsKey) ?? '0') ?? 0;
    final configured = await isPinConfigured();
    _state = configured ? AppLockState.locked : AppLockState.uninitialised;
    notifyListeners();
  }

  Future<bool> isPinConfigured() => _store.contains(_pinKey);

  Future<bool> isBiometricEnabled() async =>
      (await _store.read(_biometricEnabledKey)) == 'true';

  Future<bool> canUseBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final available = await _localAuth.canCheckBiometrics;
      return supported && available;
    } on Exception {
      return false;
    }
  }

  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on Exception {
      return const [];
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _store.write(_biometricEnabledKey, enabled.toString());
    notifyListeners();
  }

  /// Sets the first PIN, or changes it when [currentPin] verifies.
  Future<bool> setPin(String pin, {String? currentPin}) async {
    if (await isPinConfigured()) {
      if (currentPin == null || !await _verifyPin(currentPin)) return false;
    }
    await _store.write(_pinKey, PinHasher.hash(pin));
    await _resetFailures();
    _state = AppLockState.unlocked;
    notifyListeners();
    return true;
  }

  /// Removes the PIN entirely, turning app lock off. Biometric unlock is
  /// cleared with it, because biometrics exist only as a shortcut on top of the
  /// mandatory PIN fallback — leaving it enabled with no PIN would be a lock
  /// with no way in. Only callable while unlocked (you reach it from Settings),
  /// so no current-PIN check is needed.
  Future<void> clearPin() async {
    await _store.delete(_pinKey);
    await _store.write(_biometricEnabledKey, 'false');
    await _resetFailures();
    _state = AppLockState.uninitialised;
    notifyListeners();
  }

  Future<UnlockFailure?> unlockWithPin(String pin) async {
    if (isThrottled) return UnlockFailure.throttled;

    if (!await _verifyPin(pin)) {
      _failedAttempts++;
      await _store.write(_failedAttemptsKey, '$_failedAttempts');
      notifyListeners();
      return isThrottled ? UnlockFailure.throttled : UnlockFailure.wrongPin;
    }

    await _resetFailures();
    _state = AppLockState.unlocked;
    notifyListeners();
    return null;
  }

  Future<UnlockFailure?> unlockWithBiometrics() async {
    if (isThrottled) return UnlockFailure.throttled;
    if (!await canUseBiometrics() || !await isBiometricEnabled()) {
      return UnlockFailure.biometricUnavailable;
    }

    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock to access patient records',
        // Biometric only: falling back to the device passcode here would let
        // anyone who knows the phone's unlock code into the patient records.
        biometricOnly: true,
        // Survives the app being backgrounded by the system biometric prompt
        // rather than failing the attempt.
        persistAcrossBackgrounding: true,
      );
      if (!ok) return UnlockFailure.biometricFailed;
    } on Exception {
      return UnlockFailure.biometricUnavailable;
    }

    await _resetFailures();
    _state = AppLockState.unlocked;
    notifyListeners();
    return null;
  }

  void lock() {
    if (_state == AppLockState.uninitialised) return;
    _state = AppLockState.locked;
    _backgroundedAt = null;
    notifyListeners();
  }

  /// Records when the app left the foreground so [onResumed] can decide
  /// whether enough time passed to warrant re-authentication.
  void onBackgrounded(DateTime now) {
    if (_state != AppLockState.unlocked) return;
    _backgroundedAt = now;
  }

  void onResumed(DateTime now) {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || _state != AppLockState.unlocked) return;
    if (now.difference(since) >= backgroundLockTimeout) lock();
  }

  Future<bool> _verifyPin(String pin) async {
    final stored = await _store.read(_pinKey);
    if (stored == null) return false;
    return PinHasher.verify(pin, stored);
  }

  Future<void> _resetFailures() async {
    _failedAttempts = 0;
    await _store.write(_failedAttemptsKey, '0');
  }
}
