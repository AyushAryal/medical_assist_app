import '../cohort/query_router.dart';
import '../assist_request.dart';
import '../intent.dart';
import '../interpreter.dart';
import '../cohort/projection_parser.dart';
import '../preprocess.dart';

/// The primary interpreter: dictionary and pattern matching, no model.
///
/// First in the chain, and on this app it answers almost everything. That is a
/// property of the problem rather than a limitation accepted reluctantly — the
/// schema is eleven tables with a closed clinical vocabulary, so the space of
/// sensible questions is small enough to enumerate. Enumerating it buys
/// exactness, zero latency, no download, identical behaviour on every device,
/// and an answer that can be shown back and argued with.
///
/// Where it genuinely cannot help it declines, and the chain moves on.
class PatternInterpreter implements Interpreter {
  const PatternInterpreter();

  @override
  bool canRead(AssistRequest request) => request.hasText;

  @override
  String get name => 'pattern matching';

  /// Coded logic. Nothing downstream badges this as generated, because it is
  /// not — and calling hand-written matching "AI" devalues the badge in the
  /// places it genuinely matters.
  @override
  String? get modelName => null;

  @override
  Future<AssistIntent?> interpret(
    AssistRequest request,
    Preprocessed input,
  ) async {
    // Identifiers are restored first: an MRN lookup is exactly the kind of
    // thing this interpreter should handle, and it is coded logic, so the
    // redaction that protects a model is not needed here.
    var text = Preprocessor.restore(input);

    // "As a table" is a rendering preference, not a filter — peeled off so
    // the router never sees it, remembered so the answer opens in the view
    // that was asked for.
    final wantsTable =
        RegExp(r'\b(?:as|in) a table\b|\btabular\b').hasMatch(text);
    if (wantsTable) {
      text = text
          .replaceAll(RegExp(r'\b(?:as|in) a table\b|\btabular\b'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    // Likewise the projection: "and their contact numbers" changes what the
    // table shows, never who is on it, so the router sees the question
    // without it and filters identically.
    final projection = ProjectionParser.parse(text);
    text = projection.rest;

    final routed = QueryRouter.route(text, asOf: request.now);
    if (routed == null) return null;

    // A question about distribution rather than membership. "How many by
    // month", "broken down by age" — answering those with a list is what
    // makes reporting unusable.
    if (_reportKind(text) case final kind?) {
      return ReportIntent(
        kind: kind,
        query: routed.query,
        confidence: routed.confidence,
        matched: routed.matched,
      );
    }

    return QueryIntent(
      query: routed.query,
      confidence: routed.confidence,
      matched: <String>[
        ...routed.matched,
        for (final field in projection.fields)
          'showing ${field.label.toLowerCase()}',
      ],
      projection: projection.fields,
      // A projection is a request for columns, so the table leads even
      // unasked; the tappable list stays one toggle away.
      preferTable: wantsTable || projection.fields.isNotEmpty,
    );
  }

  /// What each breakdown sounds like when someone asks for it.
  ///
  /// Exposed, and a map rather than a chain of ifs, because two other things
  /// depend on this being one list: follow-up buttons append
  /// [ReportKindX.phrase] and would otherwise be able to offer wording this
  /// does not recognise, and stripping a cut back off a question needs to
  /// remove exactly what matched. Order is significant — the first match wins.
  static final Map<ReportKind, RegExp> reportPatterns = <ReportKind, RegExp>{
    ReportKind.activityOverTime: RegExp(
      r'\b(?:per|each|by) (?:day|week|month)\b|\bover time\b|\btrend\b',
    ),
    ReportKind.byAgeBand: RegExp(
      r'\b(?:broken down |grouped )?by age(?: band| group| breakdown)?\b|'
      r'\bage (?:band|group|breakdown)\b',
    ),
    ReportKind.bySex: RegExp(r'\b(?:broken down |grouped )?by (?:sex|gender)\b'),
    ReportKind.byVisitType:
        RegExp(r'\b(?:broken down |grouped )?by (?:visit )?type\b'),
    ReportKind.byStatus: RegExp(
      r'\b(?:broken down |grouped )?by status\b|\bbreakdown of status\b',
    ),
  };

  static ReportKind? _reportKind(String text) => reportKindIn(text);

  /// The report cut a fragment asks for, if any. Public because the
  /// conversation layer reads cuts off fragments — "by sex" after
  /// "diabetics" — and must read them with exactly these patterns.
  static ReportKind? reportKindIn(String text) {
    for (final entry in reportPatterns.entries) {
      if (entry.value.hasMatch(text)) return entry.key;
    }
    return null;
  }

  /// The question with any breakdown wording taken back out.
  ///
  /// So that re-cutting an answer replaces the cut rather than stacking it:
  /// without this, tapping through three follow-ups leaves "visits per week by
  /// age band by sex", which matches the first pattern and silently ignores
  /// the rest — a button that appears to do nothing.
  static String withoutReportPhrase(String text) {
    var out = text;
    for (final pattern in reportPatterns.values) {
      out = out.replaceAll(pattern, ' ');
    }
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
