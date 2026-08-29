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

  /// Rewrites a plan as instructions a patient can follow at home.
  Future<LanguageModelDraft> plainLanguageInstructions(String plan);

  /// Rewrites a structured SBAR handoff as a short paragraph a clinician could
  /// read aloud at a shift change. Rewriting, not authorship: it is handed the
  /// deterministic handoff the app already built and asked only to reshape it,
  /// keeping every fact and adding none — a "not recorded" stays "not
  /// recorded". The deterministic handoff remains the source of truth; this is
  /// a convenience draft, marked as generated.
  Future<LanguageModelDraft> spokenHandoff(String structuredHandoff);

  /// Rewrites a structured record summary as a one-paragraph spoken brief to
  /// hear before walking into a consultation. Rewriting only: keep every fact,
  /// add none, keep "not recorded" as not recorded.
  Future<LanguageModelDraft> spokenBrief(String structuredSummary);

  /// Writes a short, warm, plain-language reminder for a patient whose review
  /// is due, from the facts given. No medical advice and no new facts — it
  /// reshapes an appointment reminder, nothing more.
  Future<LanguageModelDraft> patientReminder(String reviewContext);

  /// Lists a few focused questions or examination points a clinician might
  /// *consider* for a presentation — prompts, explicitly not a diagnosis or
  /// instructions, and adding no facts. The weakest-guarantee task here, so
  /// its output is framed as suggestions only and always marked generated.
  Future<LanguageModelDraft> triageTalkingPoints(String presentation);

  /// Says which SOAP section each numbered sentence belongs to.
  ///
  /// Classification, not generation — the reply is expected to be section
  /// names and numbers, and the caller assembles the note from its *own*
  /// sentences by index. That is what makes it impossible for a model to
  /// change a word of a clinical note here, rather than merely detectable.
  ///
  /// Returns the raw reply for the caller to parse, or null when the model
  /// could not answer; a null is not an error, it is the rules keeping the
  /// sentences they already placed.
  Future<String?> assignSentencesToSections(List<String> numberedSentences);

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

  /// Reads a free-spoken description of measurements into a JSON object keyed
  /// by the given [fields] (their ids), or null when the model cannot.
  ///
  /// Extraction, not authorship: the reply is expected to be JSON of
  /// field → value, and every value is then validated against the field's kind
  /// and bounds before use, so a hallucinated field or an impossible number is
  /// discarded rather than entered. Returns the raw reply for the caller to
  /// parse and validate; null is not an error.
  Future<String?> extractValues(
    String description, {
    required List<String> fields,
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

  /// A generic caution for any generated text. Features that need something
  /// more specific (a note draft, a message to send) pass their own wording —
  /// this is only the fallback, deliberately task-neutral.
  static const String generatedNotice =
      'Generated by the assistant. Read it before you rely on it — the record '
      'is what you keep, not what was suggested.';
}
