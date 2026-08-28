import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../core/smart_phrases/smart_phrase.dart';
import '../../../core/smart_phrases/smart_phrase_field.dart';
import '../../../data/models/attachment.dart';
import '../../attachments/attachment_strip.dart';
import '../../attachments/field_attach_bar.dart';

/// One of the four SOAP sections: a titled text box with its own attachment
/// bar and, when a model is installed, a drafting action beneath it.
class SoapField extends StatelessWidget {
  const SoapField({
    super.key,
    required this.letter,
    required this.title,
    required this.hint,
    required this.controller,
    required this.enabled,
    required this.attachments,
    required this.paths,
    required this.onCaptured,
    required this.onDeleteAttachment,
    required this.onDictate,
    required this.onTranscribe,
    required this.transcribingId,
    this.aiAction,
    this.isGenerated = false,
    this.focusNode,
    this.smartPhrases,
    this.scope = const SmartPhraseScope(),
  });

  final String letter;
  final String title;
  final String hint;
  final TextEditingController controller;
  final FocusNode? focusNode;

  /// The smart-phrase vocabulary, and the patient this note is about, so a `\`
  /// menu here can fetch this patient's record.
  final SmartPhraseRegistry? smartPhrases;
  final SmartPhraseScope scope;
  final bool enabled;
  final List<Attachment> attachments;
  final Map<String, String> paths;
  final Future<void> Function({
    required File file,
    required AttachmentKind kind,
    String? mimeType,
    int? durationMs,
  }) onCaptured;
  final void Function(Attachment) onDeleteAttachment;
  final VoidCallback onDictate;
  final void Function(Attachment)? onTranscribe;
  final String? transcribingId;

  /// A model-drafting action for this section — sort, reword — or null when
  /// no model is installed or the section has none. Rendered under the text
  /// so the field itself stays what it is everywhere else in the app.
  final Widget? aiAction;

  /// True while this section holds text the model wrote and nobody has edited.
  /// The badge comes off on the first keystroke — the rule the design system
  /// states for generated content everywhere.
  final bool isGenerated;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return SectionCard(
      title: title,
      leading: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.primaryContainer,
          borderRadius: BorderRadius.circular(m.radiusSm - 2),
        ),
        child: Text(
          letter,
          style: context.texts.labelLarge
              ?.copyWith(color: palette.onPrimaryContainer),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isGenerated) ...<Widget>[
            // Short label — the section title is right beside it, so "AI" reads
            // clearly without the width of "AI generated".
            const AiBadge(label: 'AI', dense: true),
            SizedBox(width: m.spaceXs),
          ],
          FieldAttachBar(
            enabled: enabled,
            onCaptured: onCaptured,
            onDictate: onDictate,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _wrapSmart(
            TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              maxLines: null,
              minLines: 3,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: context.texts.bodyMedium,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ?aiAction,
          // Evidence sits under the text it belongs to, playable and viewable
          // in place — never filed away on a separate screen.
          AttachmentStrip(
            attachments: attachments,
            paths: paths,
            onDelete: enabled ? onDeleteAttachment : null,
            onTranscribe: onTranscribe,
            transcribingId: transcribingId,
          ),
        ],
      ),
    );
  }

  Widget _wrapSmart(Widget field) {
    final registry = smartPhrases;
    final node = focusNode;
    final ctrl = controller;
    if (registry == null || node == null || ctrl is! SmartPhraseController) {
      return field;
    }
    return SmartPhraseField(
      controller: ctrl,
      focusNode: node,
      registry: registry,
      scope: scope,
      child: field,
    );
  }
}
