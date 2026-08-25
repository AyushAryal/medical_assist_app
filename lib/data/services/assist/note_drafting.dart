import 'language_model.dart';

/// Why a draft was refused, in words a clinician can act on.
class DraftRefused implements Exception {
  const DraftRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// A dictation sorted into SOAP sections, gated and ready to preview.
class SoapDraft {
  const SoapDraft({required this.sections, required this.engineName});

  /// Section key (`subjective`…`plan`) to sorted text. Only non-empty
  /// sections appear.
  final Map<String, String> sections;
  final String engineName;
}

/// A plan reworded for the patient, ready to preview.
class InstructionsDraft {
  const InstructionsDraft({required this.text, required this.engineName});

  final String text;
  final String engineName;
}

/// The model's two note-drafting tasks, behind deterministic gates.
///
/// The model proposes; this class decides whether the proposal is even
/// allowed on screen. The distinction matters most for [sortIntoSoap]: its
/// contract is *sorting* — every sentence the clinician said, in the box it
/// belongs in, and nothing else — and a small model will sometimes summarise,
/// "correct", or invent instead. Those failures look plausible, which is
/// exactly why a human preview is not enough on its own; the gate checks the
/// property mechanically, word by word, before a clinician is ever shown the
/// draft.
///
/// The rewording task cannot be gated the same way — new words are the point
/// — so it gets weaker mechanical checks and carries its caveat into the UI
/// instead. That asymmetry is deliberate and worth keeping visible: what can
/// be verified is verified; what cannot is labelled.
abstract final class NoteDrafting {
  static const List<String> sectionKeys = <String>[
    'subjective',
    'objective',
    'assessment',
    'plan',
  ];

  /// Sorts dictated prose into SOAP sections, or refuses with the reason.
  static Future<SoapDraft> sortIntoSoap(
    LanguageModelEngine engine,
    String text,
  ) async {
    final source = text.trim();
    if (source.isEmpty) {
      throw const DraftRefused('There is nothing to sort yet.');
    }

    final draft = await engine.structureDictation(source);
    final sections = <String, String>{
      for (final key in sectionKeys)
        if ((draft.sections[key] ?? '').trim().isNotEmpty)
          key: draft.sections[key]!.trim(),
    };
    if (sections.isEmpty) {
      throw const DraftRefused(
        'The model could not read that into sections. Nothing was changed.',
      );
    }

    final sourceTokens = _tokens(source);
    final draftTokens = _tokens(sections.values.join(' '));

    // Invention check: every word in the draft must be a word the clinician
    // said. A sorted note contains no new vocabulary — a new drug name, a new
    // number, a new "not" are all corruption wearing tidiness.
    final invented = draftTokens.difference(sourceTokens);
    if (invented.isNotEmpty) {
      throw DraftRefused(
        'The model changed the words rather than sorting them '
        '(added: ${invented.take(3).join(', ')}). Nothing was changed.',
      );
    }

    // Loss check: sorting must not quietly shorten the record. Some loss of
    // filler is tolerable; losing a third of the content words is not.
    final kept = sourceTokens.intersection(draftTokens).length;
    if (kept < sourceTokens.length * 0.7) {
      throw const DraftRefused(
        'The model dropped too much of what was said. Nothing was changed.',
      );
    }

    return SoapDraft(sections: sections, engineName: draft.engineName);
  }

  /// Rewords a plan as instructions a patient can follow, or refuses.
  static Future<InstructionsDraft> patientInstructions(
    LanguageModelEngine engine,
    String plan,
  ) async {
    final source = plan.trim();
    if (source.isEmpty) {
      throw const DraftRefused('Write the plan first.');
    }

    final draft = await engine.plainLanguageInstructions(source);
    final text = draft.text.trim();

    if (text.isEmpty) {
      throw const DraftRefused('The model produced nothing.');
    }
    if (_tokens(text).difference(_tokens(source)).isEmpty &&
        text.length >= source.length) {
      // No new words and no shorter: it echoed the plan back. An echo is not
      // a translation, here as everywhere.
      throw const DraftRefused(
        'The model repeated the plan instead of rewording it.',
      );
    }
    if (text.length > source.length * 4 + 200) {
      throw const DraftRefused(
        'The model wrote far more than the plan says, which means it was '
        'inventing. Nothing was kept.',
      );
    }

    return InstructionsDraft(text: text, engineName: draft.engineName);
  }

  static Set<String> _tokens(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9. ]'), ' ')
      // A decimal point inside a dose survives; sentence punctuation dies.
      .replaceAll(RegExp(r'\.(?!\d)'), ' ')
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toSet();
}
