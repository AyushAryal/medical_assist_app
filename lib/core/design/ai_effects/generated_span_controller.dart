import 'package:flutter/material.dart';

import '../../smart_phrases/smart_phrase.dart';
import 'generated_text.dart';

/// A text-field controller that highlights the span a model wrote.
///
/// [GeneratedText] marks generated words in static text; this does the same job
/// inside a live, editable `TextField`, which is the harder half — a clinician
/// works *in* a note, so the mark has to sit under text they can still type
/// over. It highlights [generatedRange] only while the field still holds
/// exactly the [snapshot] the model produced; the first edited character breaks
/// the snapshot and the highlight falls away in the same breath as the badge,
/// which is the rule the app states everywhere for generated content.
///
/// Nothing else about the field changes — selection, composing, cursor and
/// editing all behave as normal, because only [buildTextSpan] is overridden and
/// only to recolour, never to alter the text.
class GeneratedSpanController extends SmartPhraseController {
  GeneratedSpanController({super.text});

  String? _snapshot;
  TextRange? _range;

  /// Records that [range] of the current text is model-written, valid only
  /// while the whole field still equals [snapshot].
  void markGenerated({required String snapshot, required TextRange range}) {
    _snapshot = snapshot;
    _range = range;
    notifyListeners();
  }

  /// Forgets any generated span — for a fresh load, where nothing on screen was
  /// written this session.
  void clearGenerated() {
    if (_snapshot == null && _range == null) return;
    _snapshot = null;
    _range = null;
    notifyListeners();
  }

  bool get _highlighting {
    final snapshot = _snapshot;
    final range = _range;
    return snapshot != null &&
        range != null &&
        text == snapshot &&
        range.start >= 0 &&
        range.end <= text.length &&
        range.start < range.end;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!_highlighting) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final range = _range!;
    // The same flat light-orange highlighter as GeneratedText, sitting under
    // text a clinician can edit; the mark stays until the first keystroke.
    final generated = TextStyle(
      backgroundColor: generatedHighlightColor(context),
    );

    return TextSpan(
      style: style,
      children: <InlineSpan>[
        if (range.start > 0) TextSpan(text: text.substring(0, range.start)),
        TextSpan(
          text: text.substring(range.start, range.end),
          style: generated,
        ),
        if (range.end < text.length) TextSpan(text: text.substring(range.end)),
      ],
    );
  }
}
