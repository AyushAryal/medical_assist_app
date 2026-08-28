import 'package:flutter/material.dart';

import '../../../clinical/insights/note_intelligence.dart';
import '../../../core/design/design.dart';

/// Structured entries the written text implies, offered rather than applied.
///
/// This exists because of a specific, ordinary failure: a clinician writes
/// "started on amlodipine 5mg" in the plan and the medication list still says
/// nothing. Six months later the medication list is not trustworthy enough to
/// prescribe against. Every row here is one tap to file and one tap to
/// dismiss, and dismissal is remembered so the same suggestion does not
/// reappear on the next keystroke.
class SuggestionPanel extends StatelessWidget {
  const SuggestionPanel({
    super.key,
    required this.suggestions,
    required this.onAccept,
    required this.onDismiss,
  });

  final List<ExtractedTerm> suggestions;
  final Future<void> Function(ExtractedTerm) onAccept;
  final void Function(ExtractedTerm) onDismiss;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return SectionCard(
      title: 'From your note',
      subtitle: 'Nothing is filed until you tap it',
      leading: const AiSparkleIcon(size: 20),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AiBadge(label: 'Suggested', dense: true),
          InfoDot(
            explanation: NoteIntelligence.explain(suggestions.length),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final term in suggestions)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceSm),
              child: Row(
                children: <Widget>[
                  Icon(
                    switch (term.kind) {
                      ExtractedTermKind.medication =>
                        Icons.medication_outlined,
                      ExtractedTermKind.problem => Icons.checklist_outlined,
                      ExtractedTermKind.allergy =>
                        Icons.warning_amber_outlined,
                      ExtractedTermKind.redFlag => Icons.priority_high,
                      ExtractedTermKind.followUp =>
                        Icons.event_available_outlined,
                    },
                    size: 17,
                    color: term.kind == ExtractedTermKind.redFlag
                        ? palette.critical
                        : palette.onSurfaceMuted,
                  ),
                  SizedBox(width: m.spaceSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(term.text, style: context.texts.bodyMedium),
                        Text(
                          '${term.kind.label} · from "${term.matchedPhrase}"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  // A red flag is a prompt to think, not a record to file, so
                  // it gets no "add" action — only acknowledgement.
                  if (term.kind != ExtractedTermKind.redFlag)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Add to chart',
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: () => onAccept(term),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => onDismiss(term),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
