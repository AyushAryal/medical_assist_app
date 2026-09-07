/// Public surface of the lock module.
///
/// The unlock gate, lock screen and PIN setup. The app shell and settings
/// import THIS file, not the internals.
library;

export 'lock_gate.dart' show LockGate;
export 'lock_screen.dart' show LockScreen;
export 'pin_setup_screen.dart' show PinSetupScreen;
