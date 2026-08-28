import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// Asks the clinician to confirm an action, returning true only on confirm.
///
/// The same title / message / Cancel + confirm `AlertDialog` was written out
/// at every call site — signing a note, signing an encounter, removing a
/// model, deleting a phrase. One helper keeps the wording structure and the
/// button order identical everywhere, so "the confirm button is on the right
/// and says what it does" is not re-decided per screen.
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
  final result = await showDialog<bool>(
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
