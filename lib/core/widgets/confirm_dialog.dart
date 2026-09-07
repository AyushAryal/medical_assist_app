import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// Asks the clinician to confirm an action, returning true only on confirm.
///
/// Platform-adaptive: a `CupertinoAlertDialog` on iOS and an `AlertDialog` on
/// Android, so a confirm prompt matches the muscle memory of the OS it runs on
/// — the button order, the destructive-red convention and the presentation are
/// each the native one. The wording and semantics are identical either way.
///
/// Returns false when dismissed (barrier tap, back button) as well as on
/// Cancel, so callers can treat anything but an explicit confirm as "no".
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final bool isCupertino = Theme.of(context).platform == TargetPlatform.iOS;

  final bool? result = isCupertino
      ? await showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: Text(title),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(message),
            ),
            actions: <Widget>[
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(cancelLabel),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(true),
                isDefaultAction: !destructive,
                isDestructiveAction: destructive,
                child: Text(confirmLabel),
              ),
            ],
          ),
        )
      : await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(cancelLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: context.palette.critical,
                      )
                    : null,
                child: Text(confirmLabel),
              ),
            ],
          ),
        );
  return result ?? false;
}
