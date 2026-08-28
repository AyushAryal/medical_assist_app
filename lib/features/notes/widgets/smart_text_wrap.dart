import 'package:flutter/material.dart';

import '../../../core/smart_phrases/smart_phrase.dart';
import '../../../core/smart_phrases/smart_phrase_field.dart';

/// Wraps [field] in a [SmartPhraseField] when everything a `\` menu needs is
/// present — a registry, a focus node, and a [SmartPhraseController] — and
/// otherwise returns the field unchanged.
///
/// Both the SOAP sections and the working-notes box are plain text fields that
/// become smart-phrase fields under the same three conditions; this is that
/// one condition, written once.
Widget smartTextWrap({
  required Widget field,
  required TextEditingController controller,
  FocusNode? focusNode,
  SmartPhraseRegistry? registry,
  SmartPhraseScope scope = const SmartPhraseScope(),
}) {
  if (registry == null ||
      focusNode == null ||
      controller is! SmartPhraseController) {
    return field;
  }
  return SmartPhraseField(
    controller: controller,
    focusNode: focusNode,
    registry: registry,
    scope: scope,
    child: field,
  );
}
