/// The seam a small on-device language model would plug into.
///
/// No implementation ships. The interface exists now because the decision it
/// encodes is a governance decision, not a technical one, and it is far easier
/// to hold a line that was drawn before the model arrived than to retrofit it
/// afterwards:
///
/// * **Every output is a draft.** [LanguageModelDraft] has no path to a signed
///   note. Nothing generated can be saved without a clinician reading it and
///   accepting it, and the UI marks it as generated until they do.
/// * **The model never sees more than it needs.** Callers pass the text the
///   clinician is working on, not a patient record.
/// * **It runs on the device or it does not run.** An implementation whose
///   [runsOnDevice] is false must be refused by the UI unless an operator has
///   explicitly accepted it, exactly as with transcription.
/// * **It is never in the critical path.** Every feature built on this must
///   work with [LanguageModelEngine] absent, because on most devices it will
///   be. The deterministic extractors in `clinical/insights/` are the product;
///   this only ever adds to them.
///
/// A small model — on the order of a few hundred million parameters, which is
/// what fits — is good at reshaping text it has been given and unreliable at
/// anything requiring knowledge. That is why the tasks below are all
/// rewriting, and why none of them is "suggest a diagnosis".
abstract interface class LanguageModelEngine {
  String get name;

  /// Whether inference happens on this device. See the note above.
  bool get runsOnDevice;

  Future<bool> isReady();

  /// Reshapes dictated prose into the four SOAP sections.
  ///
  /// The task is *sorting sentences the clinician said into the right boxes* —
  /// nothing may be added, and nothing may be summarised away.
  Future<LanguageModelDraft> structureDictation(String transcript);

  /// Rewrites a plan as instructions a patient can follow at home.
  Future<LanguageModelDraft> plainLanguageInstructions(String plan);

  /// Rewrites a free-form request as one of the question forms the coded
  /// interpreters answer, or returns null when none fits.
  ///
  /// This is the assistant's model contract, and its shape is the whole
  /// safety argument: the model **never produces an intent, a filter or a
  /// query** — it produces *a sentence*, and the sentence then goes through
  /// the same grammars, the same validation and the same authorisation as if
  /// the clinician had typed it. A hallucinated rewrite therefore fails
  /// loudly (it does not parse) instead of silently querying the wrong thing,
  /// and the provenance trail shows both the original wording and the
  /// rewrite it ran.
  ///
  /// [vocabulary] is the same published question bank the guide shows, passed
  /// in so the prompt and the UI can never advertise different capabilities.
  Future<String?> rephraseAsKnownQuestion(
    String request, {
    required List<String> vocabulary,
  });

  Future<void> dispose();
}

/// Generated text, permanently marked as such.
class LanguageModelDraft {
  const LanguageModelDraft({
    required this.text,
    required this.engineName,
    this.sections = const <String, String>{},
  });

  final String text;
  final String engineName;

  /// Section name to content, where the task produced structured output.
  final Map<String, String> sections;

  /// Shown wherever generated text appears, and carried into the note until
  /// the clinician edits it.
  static const String provenanceNotice =
      'Drafted automatically from your dictation. Check every line before '
      'signing — the record is what you sign, not what was suggested.';
}
