import '../insights/note_intelligence.dart';
import 'clinical_flag.dart';

/// Derives red-flag [ClinicalFlag]s from free text — a triage complaint, a
/// booking reason, a note.
///
/// Reuses [NoteIntelligence]'s fixed red-flag dictionary rather than inventing
/// a second one: the phrases that should stop a clinician mid-note are the same
/// phrases that should pull a patient up the triage board. Dictionary matching,
/// not inference — instant, offline, and exactly predictable, with negation
/// ("denies chest pain") already handled by the extractor.
abstract final class RedFlagRule {
  static List<ClinicalFlag> fromText(
    String subjectId,
    String? text, {
    required String source,
  }) {
    if (text == null || text.trim().isEmpty) return const <ClinicalFlag>[];

    final seen = <String>{};
    final flags = <ClinicalFlag>[];
    for (final term in NoteIntelligence.extract(text)) {
      if (term.kind != ExtractedTermKind.redFlag) continue;
      if (!seen.add(term.text)) continue;
      flags.add(
        ClinicalFlag(
          subjectId: subjectId,
          kind: FlagKind.redFlag,
          severity: FlagSeverity.critical,
          title: term.text,
          reason: 'Mentioned: "${term.matchedPhrase}"',
          source: source,
        ),
      );
    }
    return flags;
  }
}
