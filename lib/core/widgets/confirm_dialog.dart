import 'package:flutter/widgets.dart';
import 'package:opt_kit/opt_kit.dart' show showOptConfirmDialog;

/// Asks the clinician to confirm an action, returning true only on confirm.
///
/// A thin wrapper over the kit's canonical [showOptConfirmDialog] so call
/// sites keep their existing name and signature. The kit dialog is
/// platform-adaptive (Cupertino on Apple, Material elsewhere), marks the
/// confirm action destructive-red when [destructive] is set, and resolves to
/// false on cancel or barrier dismissal — same contract this helper always
/// had. Only the default confirm label differs from the kit ('Confirm'
/// rather than 'OK'), preserved here so existing prompts read unchanged.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) =>
    showOptConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
    );
