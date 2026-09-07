import '../../data/services/assist/note_drafting.dart';

/// One section's proposal, and what the clinician decided about it.
class SectionProposal {
  SectionProposal({
    required this.key,
    required this.title,
    required this.before,
    required this.proposed,
    required this.sentences,
    this.keep = true,
  });

  final String key;
  final String title;

  /// What is in the field now. Shown above the proposal so the change is
  /// visible as a change, not as a block of text to compare from memory.
  final String before;

  /// What the model suggests adding to this section.
  final String proposed;

  /// The proposed text broken out sentence by sentence, each tagged with
  /// whether the model or the rules filed it. Same words as [proposed]; the
  /// tags are what let the screen mark the model's decisions.
  final List<DraftSentence> sentences;

  /// Accepted by default — the draft has already passed the word-for-word
  /// gate, and defaulting to discard would make the common case four extra
  /// taps. Every one is still individually refusable.
  bool keep;

  bool get isAddition => before.trim().isNotEmpty;

  /// Whether the model filed any sentence in this section — the only case the
  /// marking, and the caption explaining it, need to appear at all.
  bool get hasModelPlaced => sentences.any((s) => s.placedByModel);
}
