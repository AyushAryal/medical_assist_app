import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../core/smart_phrases/smart_phrase.dart';
import 'smart_text_wrap.dart';

/// The rough-draft box that sits above the four sections.
///
/// It exists because the SOAP structure describes where a note *ends up*, not
/// how it is produced: a clinician talks through a consultation in the order
/// it happened, and asking them to pre-sort into four boxes as they speak is
/// asking them to do the work the structure was supposed to save.
///
/// So this is a plain scratch box with a microphone, and — when a model is
/// installed — one button that distributes what is in it. Without a model it
/// is still useful on its own: somewhere to put words while a patient is
/// still talking. It is deliberately not part of the signed record, and the
/// editor refuses to sign quietly while anything is still sitting in it.
class WorkingNotesCard extends StatelessWidget {
  const WorkingNotesCard({
    super.key,
    required this.controller,
    required this.hasModel,
    required this.isDrafting,
    required this.onSort,
    required this.onDictate,
    required this.onScan,
    this.focusNode,
    this.smartPhrases,
    this.scope = const SmartPhraseScope(),
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final SmartPhraseRegistry? smartPhrases;
  final SmartPhraseScope scope;
  final bool hasModel;
  final bool isDrafting;
  final VoidCallback onSort;
  final VoidCallback onDictate;

  /// Scan text off a photo of a page into the working notes.
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasText = controller.text.trim().isNotEmpty;

        return SectionCard(
          title: 'Working notes',
          subtitle: 'Talk or type it all here — sort it after',
          leading: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: BorderRadius.circular(m.radiusSm - 2),
            ),
            child: Icon(
              Icons.edit_note,
              size: 18,
              color: palette.onSurfaceMuted,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Scan text from a photo',
                icon: const Icon(Icons.document_scanner_outlined),
                onPressed: onScan,
              ),
              IconButton(
                tooltip: 'Dictate into the working notes',
                icon: const Icon(Icons.mic_none_outlined),
                onPressed: onDictate,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              smartTextWrap(
                controller: controller,
                focusNode: focusNode,
                registry: smartPhrases,
                scope: scope,
                field: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLines: null,
                  minLines: 3,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: context.texts.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Whatever the consultation produced, in any '
                        'order. Nothing here is part of the signed note.',
                    hintStyle: context.texts.bodySmall
                        ?.copyWith(color: palette.onSurfaceMuted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (hasText) ...<Widget>[
                SizedBox(height: m.spaceSm),
                AiGlowBorder(
                  active: isDrafting,
                  borderRadius: BorderRadius.circular(m.radiusSm),
                  child: FilledButton.tonalIcon(
                    onPressed: isDrafting ? null : onSort,
                    icon: isDrafting
                        ? const AiSparkleIcon(size: 18)
                        : const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text(
                      isDrafting ? 'Sorting…' : 'Sort into S · O · A · P',
                    ),
                  ),
                ),
                SizedBox(height: m.spaceXs),
                Text(
                  hasModel
                      ? 'Sorted by the note rules first; the model places '
                          'whatever they cannot. Nothing is reworded.'
                      : 'Sorted by the note rules — "on examination", '
                          '"likely", "review in a week". An assistant model '
                          'in Settings › On-device AI places the rest.',
                  style: context.texts.labelSmall
                      ?.copyWith(color: palette.onSurfaceMuted),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
