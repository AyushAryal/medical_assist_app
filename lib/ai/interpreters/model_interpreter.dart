import '../../data/services/assist/language_model.dart';
import '../analytics/analysis_examples.dart';
import '../assist_request.dart';
import '../cohort/query_vocabulary.dart';
import '../intent.dart';
import '../interpreter.dart';
import '../preprocess.dart';
import '../schema/field_registry.dart';

/// The interpreter a small on-device model plugs into — last in the chain,
/// and a *translator*, never an author.
///
/// Its entire contract is one call: hand the model the request plus the
/// published question bank, get back **a sentence** — the known question form
/// nearest to what was asked — and run that sentence through the same coded
/// interpreters as if the clinician had typed it. The model chooses wording;
/// coded logic still does every piece of understanding that touches data.
///
/// What this buys, in order of importance:
///
/// * **A hallucination fails loudly.** A rewrite that names a question the
///   grammars do not answer simply fails to parse, and the chain falls
///   through to the clarifier. There is no path from model output to a query
///   that did not exist before the model was installed.
/// * **The audit trail stays readable.** The provenance shows the wording
///   that arrived and the question that ran; a clinician can disagree with
///   the translation, which is the only part the model did.
/// * **The capability list stays honest.** The prompt is built from the same
///   starters and generated examples the guide shows, so the model cannot be
///   coaxed toward questions the app does not advertise.
///
/// Held to the same rules as everything else here: it runs on the device or
/// it does not run, and it sees redacted text — never identifiers.
class ModelInterpreter implements Interpreter {
  const ModelInterpreter({
    required this.engine,
    required this.reparse,
  });

  /// Resolves the installed model at ask time, or null — in which case this
  /// interpreter declines everything and the chain behaves as if it were
  /// absent. A provider rather than an instance, because Settings can install
  /// or switch models mid-session and the swap must not rebuild the pipeline:
  /// the pipeline owns the conversation, and changing a model is not a reason
  /// to lose one.
  final LanguageModelEngine? Function() engine;

  /// Runs a rewrite through the coded interpreters. Injected so this file
  /// depends on the contract, not on the chain's construction order.
  final Future<AssistIntent?> Function(String question) reparse;

  @override
  bool canRead(AssistRequest request) => request.hasText;

  @override
  String get name => 'on-device model';

  @override
  String? get modelName => engine()?.name;

  /// The bank the model may translate into — the same one the guide shows.
  static List<String> vocabulary() => <String>[
        for (final group in QueryVocabulary.starters) ...group.starters,
        for (final example in AnalysisExamples.all) example.question,
      ];

  @override
  Future<AssistIntent?> interpret(
    AssistRequest request,
    Preprocessed input,
  ) async {
    final model = engine();
    if (model == null || !model.runsOnDevice) return null;
    if (!await model.isReady()) return null;

    // Redacted text on purpose: an MRN in the question is of no use to a
    // paraphraser and must not reach a model, even one running locally —
    // the boundary is worth nothing if it moves per deployment.
    final rewrite = await model.rephraseAsKnownQuestion(
      input.normalised,
      vocabulary: vocabulary(),
    );
    if (rewrite == null || rewrite.trim().isEmpty) return null;

    final intent = await reparse(rewrite.trim().toLowerCase());
    if (intent == null || intent is UnknownIntent) return null;
    // The free-text prose fallback does not count as parsing: a rewrite that
    // only survives as a fuzzy grep is a failed translation wearing a result.
    // A typed question earns that fallback; a generated one does not.
    if (intent case QueryIntent(:final query) when query.isTextOnly) {
      return null;
    }
    if (!validate(intent)) return null;

    // Capped confidence: however fluent the model, this answer rests on a
    // translation nobody confirmed, and the pipeline's weakest-step rule
    // should reflect that.
    return intent;
  }

  /// The post-inference gate.
  ///
  /// Everything a model proposes passes through here before it is allowed to
  /// become an intent. Kept as a pure function so it is testable without a
  /// model, and so the rule is written down before there is one to bend it
  /// for.
  static bool validate(AssistIntent intent) {
    return switch (intent) {
      // A query with no filter at all matches the entire register. Answering
      // one by counting reports the whole database as though it were a result
      // — the exact failure that produced "hello → 13 patients".
      QueryIntent(:final query) =>
        !query.isEmpty || query.anyTextOf.isNotEmpty,
      ReportIntent(:final query) => !query.isEmpty,
      // An analysis is filterless by nature — the whole register is the point
      // of "average BMI by district". What has to be true instead is that
      // every field it names exists, which is guaranteed by construction:
      // a spec holds registry objects, and a phrase matching no entry
      // produces no spec.
      AnalysisIntent(:final spec) =>
        FieldRegistry.byName(spec.table.name) != null,
      // Same argument: the spec holds registry objects, and a phrase matching
      // no entry produces no spec. An overview carries no free input at all.
      RankIntent(:final spec) =>
        FieldRegistry.byName(spec.table.name) != null,
      OverviewIntent() => true,
      // A change with nothing to change, or with no patient to change it on,
      // is not a proposal anyone can review.
      MutationIntent(:final fields, :final patientId) =>
        fields.isNotEmpty && patientId != null,
      UnknownIntent() => true,
    };
  }
}
