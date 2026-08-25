import '../core/modules/entitlements.dart';
import '../data/dao/analysis_dao.dart';
import '../data/repositories/clinical_repository.dart';
import '../data/services/assist/language_model.dart';
import 'assist_request.dart';
import 'follow_ups.dart';
import 'authorisation.dart';
import 'clarify/clarifier.dart';
import 'clarify/paraphrases.dart';
import 'conversation.dart';
import 'handlers/analysis_handler.dart';
import 'handlers/overview_handler.dart';
import 'handlers/rank_handler.dart';
import 'handlers/query_handler.dart';
import 'handlers/report_handler.dart';
import 'intent.dart';
import 'interpreter.dart';
import 'interpreters/analysis_interpreter.dart';
import 'interpreters/model_interpreter.dart';
import 'interpreters/overview_interpreter.dart';
import 'interpreters/rank_interpreter.dart';
import 'interpreters/pattern_interpreter.dart';
import 'preprocess.dart';
import 'refinement/refiner.dart';
import 'presentation.dart';
import 'provenance.dart';

/// Everything one request produced.
class AssistResult {
  const AssistResult({
    required this.request,
    required this.intent,
    required this.presentation,
    required this.provenance,
    this.secondary,
    this.followUps = const <FollowUp>[],
  });

  final AssistRequest request;
  final AssistIntent intent;
  final Presentation presentation;

  /// The stage-by-stage trail. Shown behind the info control on every answer.
  final Provenance provenance;

  /// An additional, weaker result shown alongside — records found in prose
  /// when the structured filters found their own. Deliberately never merged
  /// into the primary count.
  final Presentation? secondary;

  /// The next questions worth a tap, given what this answer turned out to be.
  ///
  /// Offered rather than left to be guessed: the person reading a count cannot
  /// know which re-cuts this app supports, and each of these hands the pipeline
  /// a question it already answers instead of one it has to infer.
  final List<FollowUp> followUps;

  /// True when a model contributed anything. Drives the generated badge, and
  /// only that: a deterministic answer is not badged, because calling
  /// hand-written matching "AI" devalues the badge where it matters.
  bool get isGenerated => provenance.involvedModel;
}

/// The assistant, end to end.
///
/// One path from a question to an answer, with named stages:
///
/// ```
///   preprocess  →  interpret  →  authorise  →  execute  →  present
/// ```
///
/// The shape earns its keep in three specific ways.
///
/// **One implementation.** The bubble and the full page previously each had
/// their own copy of the middle of this, and they drifted twice — once over
/// whether a counting question should list records, once over what an
/// unmatched question does. Anything that must be right in two places is
/// eventually right in one.
///
/// **Adding an output is adding a case.** A record, a chart, a table, a change
/// awaiting confirmation — each is a [Presentation] and a handler, not a new
/// path threaded through widgets. The compiler finds every place that has to
/// change.
///
/// **Every answer can say how it got there.** A number is the product of four
/// stages, and when it is wrong the useful question is which stage was wrong.
/// The [Provenance] trail answers that; "the AI got it wrong" does not.
///
/// The stages are also where the boundaries live that this app cares about:
/// redaction happens before anything could see identifiers, authorisation
/// happens before anything executes, and mutations stop at a proposal.
class AssistPipeline {
  AssistPipeline({
    required ClinicalRepository repository,
    required Entitlements entitlements,
    LanguageModelEngine? Function()? languageModel,
    List<Interpreter>? interpreters,
  })  : _queries = QueryHandler(repository),
        _reports = ReportHandler(repository),
        _analyses = AnalysisHandler(AnalysisDao(repository.database)),
        _ranks = RankHandler(repository, AnalysisDao(repository.database)),
        _authoriser = Authoriser(entitlements),
        _chain = InterpreterChain(
          interpreters ??
              // Coded logic first, always. The schema is eleven tables with a
              // closed clinical vocabulary, so hand-written matching covers
              // most of what anyone asks — instantly, offline, identically on
              // every device, and in a form that can be shown back and argued
              // with. A model belongs after this, filling gaps.
              const <Interpreter>[
                // Most-specific first, and each declines fast. The overview
                // vocabulary is tiny and nothing else wants it; rankings must
                // run before analysis because "patients with the highest BMI"
                // contains the words of a maximum; analysis must run before
                // the cohort matcher because "average bp by district" would
                // otherwise be read as a free-text search. The cohort matcher
                // stays last as the broadest net. Adding a capability is
                // adding an interpreter to this list, in specificity order.
                OverviewInterpreter(),
                RankInterpreter(),
                AnalysisInterpreter(),
                PatternInterpreter(),
              ],
        ) {
    // The model, when installed, is strictly last: a translator for wordings
    // the grammars miss, whose output re-enters those same grammars. See
    // ModelInterpreter for the whole argument.
    if (languageModel != null && interpreters == null) {
      _chain = InterpreterChain(<Interpreter>[
        ..._chain.interpreters,
        ModelInterpreter(
          engine: languageModel,
          reparse: (question) async {
            final request = AssistRequest(
              text: question,
              source: RequestSource.programmatic,
            );
            final probe = Provenance();
            final intent = await InterpreterChain(<Interpreter>[
              const OverviewInterpreter(),
              const RankInterpreter(),
              const AnalysisInterpreter(),
              const PatternInterpreter(),
            ]).run(request, Preprocessor.run(request, probe), probe);
            return intent;
          },
        ),
      ]);
    }
  }

  final QueryHandler _queries;
  final ReportHandler _reports;
  final AnalysisHandler _analyses;
  final RankHandler _ranks;

  /// The conversation, shared by every surface that talks to this pipeline.
  ///
  /// State lives *here* and not in a widget for the same reason the pipeline
  /// itself does: the bubble and the full page are two windows onto one
  /// dialogue, and "patients on warfarin" asked in one must make "only the
  /// women" mean something in the other. It dies with the pipeline on lock —
  /// a conversation about a register is PHI.
  final AssistThread thread = AssistThread();

  /// Built lazily from the other three: the dashboard owns no computation,
  /// only composition, and constructing it from the same instances is what
  /// guarantees a tile can never disagree with the same question asked alone.
  late final OverviewHandler _overviews =
      OverviewHandler(_analyses, _ranks, _queries);
  final Authoriser _authoriser;
  InterpreterChain _chain;

  Future<AssistResult> ask(AssistRequest request) async {
    final provenance = Provenance();

    var input = Preprocessor.run(request, provenance);
    if (input.isEmpty) {
      return AssistResult(
        request: request,
        intent: const UnknownIntent(reason: 'Nothing was asked.'),
        presentation: const MessagePresentation(
          headline: 'Ask me something about the register.',
        ),
        provenance: provenance,
      );
    }

    // "Recap" is answered from the thread itself — no query, and the earlier
    // questions come back as buttons, so revisiting one is a tap.
    if (_isRecap(input.normalised) && !thread.isEmpty) {
      return AssistResult(
        request: request,
        intent: const UnknownIntent(reason: 'Recap'),
        presentation: MessagePresentation(
          headline: 'So far: ${thread.summary ?? 'nothing has stuck yet'}. '
              'Tap a question to revisit it.',
          suggestions: thread.askedSoFar.take(5).toList(),
        ),
        provenance: provenance,
      );
    }

    // Colloquial phrasings the grammars cannot structurally match are
    // rewritten onto the canonical question — and the rewrite is recorded,
    // so the answer always says which question it actually ran.
    if (Paraphrases.canonical(input.normalised) case final canonical?) {
      provenance.add(
        'reword',
        'Read it as "$canonical"',
        detail: 'The wording matched a known way of asking this.',
        confidence: 0.9,
      );
      input = Preprocessed(
        original: input.original,
        normalised: canonical,
        redactions: input.redactions,
      );
    }

    var intent = await _chain.run(request, input, provenance);

    // A fragment that changes the standing question rather than starting a
    // new one: "only the women", "per month instead", "what about visits".
    final refined = Refiner.refine(
      standing: thread.standingIntent,
      raw: request.text,
      fragment: Preprocessor.restore(input),
      standalone: intent,
      asOf: request.now,
    );
    if (refined != null) {
      intent = refined;
      provenance.add(
        'context',
        'Read as a change to "${thread.lastQuestion}"',
        detail: refined.describe().join(' · '),
        confidence: refined.confidence,
      );
    }

    // A pure free-text fallback that contains a measurement word is a
    // calculation the grammars missed, not a prose search — "average pressure
    // levels" grepped through the notes answers a question nobody asked.
    // Downgrade it to unknown so the clarifier can ask which measure.
    if (intent case QueryIntent(:final query)
        when query.isTextOnly &&
            Clarifier.measureSlot(request.text) != null) {
      provenance.add(
        'interpret',
        'Held back from a text search',
        detail: 'A measurement word suggests this asks for a calculation.',
      );
      intent = const UnknownIntent(reason: 'That reads like a calculation.');
    }

    final decision = _authoriser.check(intent, request, provenance);
    if (!decision.isAllowed) {
      return AssistResult(
        request: request,
        intent: intent,
        presentation: MessagePresentation(
          headline: decision.reason ?? 'That is not permitted here.',
        ),
        provenance: provenance,
      );
    }

    final presentation = await _execute(intent, request, provenance);
    final secondary = await _secondaryFor(intent, presentation);

    provenance.add(
      'present',
      'Shaped as ${presentation.runtimeType}',
    );

    final result = AssistResult(
      request: request,
      intent: intent,
      presentation: presentation,
      provenance: provenance,
      secondary: secondary,
      followUps: FollowUps.after(text: request.text, intent: intent),
    );

    thread.remember(AssistTurn(
      question: request.text,
      intent: intent,
      headline: presentation.headline,
    ));
    _lastResult = result;
    return result;
  }

  /// The most recent full result, for a surface that opens onto an existing
  /// conversation — expanding the bubble shows the answer already on screen
  /// instead of re-running its queries.
  AssistResult? get lastResult => _lastResult;
  AssistResult? _lastResult;

  /// Starts a new topic. The thread is the user's to end as much as to build.
  void startAfresh() {
    thread.clear();
    _lastResult = null;
  }

  static bool _isRecap(String text) => RegExp(
        r'^(?:summarise|summarize|recap|summary|so far|where were we|'
        r'what have we covered)$',
      ).hasMatch(text.trim());

  Future<Presentation> _execute(
    AssistIntent intent,
    AssistRequest request,
    Provenance provenance,
  ) async {
    switch (intent) {
      case QueryIntent():
        return _queries.run(intent, provenance);

      case ReportIntent():
        return _reports.run(intent, provenance, asOf: request.now);

      case AnalysisIntent():
        return _analyses.run(intent, provenance);

      case RankIntent():
        return _ranks.run(intent, provenance);

      case OverviewIntent():
        return _overviews.run(intent, provenance, asOf: request.now);

      case MutationIntent():
        // Described, never performed. A misread question that runs a read
        // wastes a moment; a misread question that writes to a chart puts
        // something in a medical record that nobody said. The two are not
        // comparable, so they do not share a path.
        provenance.add(
          'execute',
          'Prepared a change for confirmation',
          detail: 'Nothing is written until it is accepted.',
        );
        return ProposalPresentation(
          headline: intent.summary,
          confirmLabel: '${intent.operation.label} this',
          changes: <({String field, String from, String to})>[
            for (final entry in intent.fields.entries)
              (field: entry.key, from: '—', to: entry.value),
          ],
        );

      case UnknownIntent(:final reason, :final suggestions):
        // Before giving up, try asking back. Every option is a complete
        // question the app provably answers, so the repair is one tap.
        if (Clarifier.attempt(request.text) case final clarification?) {
          provenance.add(
            'clarify',
            'Asked a question back',
            detail: 'Part of the request pointed at something answerable.',
          );
          return ClarifyPresentation(
            headline: clarification.prompt,
            options: clarification.options,
          );
        }
        return MessagePresentation(
          headline: reason,
          suggestions: suggestions,
        );
    }
  }

  Future<Presentation?> _secondaryFor(
    AssistIntent intent,
    Presentation primary,
  ) async {
    if (intent is! QueryIntent) return null;
    if (primary is! MetricPresentation) return null;
    return _queries.mentionsFor(
      intent.query,
      exclude: <String>{for (final row in primary.rows) row.patient.id},
    );
  }
}
