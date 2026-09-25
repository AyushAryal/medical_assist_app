import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/security/app_lock_service.dart';
import 'lock_layout.dart';
import 'pin_pad.dart';

/// First-run PIN enrolment, and PIN change from settings.
///
/// A PIN is mandatory even when biometrics are available: fingerprints fail
/// with gloves or wet hands, and a clinician locked out mid-consultation is a
/// safety problem, not an inconvenience.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key, this.isFirstRun = false});

  final bool isFirstRun;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

enum _Stage { verifyCurrent, choose, confirm }

class _PinSetupScreenState extends State<PinSetupScreen> {
  static const int _pinLength = 6;

  late _Stage _stage = widget.isFirstRun ? _Stage.choose : _Stage.verifyCurrent;
  String _entry = '';
  String _currentPin = '';
  String _firstEntry = '';
  String? _message;
  bool _hasError = false;

  /// Rejects the handful of PINs that are guessed first. Deliberately narrow —
  /// an over-strict policy on a device used under time pressure just pushes
  /// people to write the PIN on the case.
  String? _weakness(String pin) {
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) {
      return 'Avoid a PIN of repeated digits.';
    }
    const sequences = '01234567890';
    const reversed = '09876543210';
    if (sequences.contains(pin) || reversed.contains(pin)) {
      return 'Avoid sequential digits.';
    }
    return null;
  }

  Future<void> _onComplete() async {
    final lock = context.read<AppLockService>();

    switch (_stage) {
      case _Stage.verifyCurrent:
        final failure = await lock.unlockWithPin(_entry);
        if (!mounted) return;
        if (failure != null) {
          setState(() {
            _entry = '';
            _hasError = true;
            _message = 'Incorrect PIN.';
          });
          return;
        }
        setState(() {
          _currentPin = _entry;
          _entry = '';
          _stage = _Stage.choose;
          _hasError = false;
          _message = null;
        });

      case _Stage.choose:
        final weakness = _weakness(_entry);
        if (weakness != null) {
          setState(() {
            _entry = '';
            _hasError = true;
            _message = weakness;
          });
          return;
        }
        setState(() {
          _firstEntry = _entry;
          _entry = '';
          _stage = _Stage.confirm;
          _hasError = false;
          _message = null;
        });

      case _Stage.confirm:
        if (_entry != _firstEntry) {
          setState(() {
            _entry = '';
            _firstEntry = '';
            _stage = _Stage.choose;
            _hasError = true;
            _message = 'The PINs did not match. Start again.';
          });
          return;
        }
        final saved = await lock.setPin(
          _entry,
          currentPin: widget.isFirstRun ? null : _currentPin,
        );
        if (!mounted) return;
        if (!saved) {
          setState(() {
            _entry = '';
            _hasError = true;
            _message = 'Could not save the PIN.';
          });
          return;
        }
        // Saved silently before: the screen just popped back to Settings with
        // nothing to say the new PIN took. The toast lands on the root
        // messenger, so it stays visible over the screen underneath.
        OptToast.success(
          context,
          widget.isFirstRun ? 'PIN set' : 'PIN updated',
        );
        if (!widget.isFirstRun && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
    }
  }

  String get _title => switch (_stage) {
        _Stage.verifyCurrent => 'Enter your current PIN',
        _Stage.choose => widget.isFirstRun ? 'Choose a PIN' : 'Choose a new PIN',
        _Stage.confirm => 'Confirm your PIN',
      };

  String get _subtitle => switch (_stage) {
        _Stage.verifyCurrent => 'Confirm it is you before changing the PIN.',
        _Stage.choose =>
          'Six digits. This unlocks the encrypted patient records on '
              'this device.',
        _Stage.confirm => 'Enter the same six digits again.',
      };

  void _onDigit(String digit) {
    if (_entry.length >= _pinLength) return;
    setState(() {
      _entry += digit;
      _hasError = false;
      _message = null;
    });
    if (_entry.length == _pinLength) _onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.isFirstRun ? null : AppBar(title: const Text('Change PIN')),
      body: LockLayout(
        header: Column(
          children: <Widget>[
            if (widget.isFirstRun) ...<Widget>[
              Icon(Icons.shield_outlined, size: 44, color: palette.primary),
              SizedBox(height: m.spaceLg),
            ],
            Text(_title, style: context.texts.headlineSmall),
            SizedBox(height: m.spaceXs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                _subtitle,
                style: context.texts.bodySmall,
                textAlign: TextAlign.center,
              ),
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
                      style: context.texts.bodySmall
                          ?.copyWith(color: palette.critical),
                    ),
            ),
          ],
        ),
        keypad: PinPad(
          onDigit: _onDigit,
          onBackspace: () {
            if (_entry.isEmpty) return;
            setState(
                () => _entry = _entry.substring(0, _entry.length - 1));
          },
        ),
      ),
    );
  }
}
