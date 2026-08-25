import '../analytics/analysis.dart';
import '../analytics/analysis_parser.dart';
import '../assist_request.dart';
import '../intent.dart';
import '../interpreter.dart';
import '../preprocess.dart';

/// Recognises analytical questions — anything with an aggregate, a breakdown
/// or a named chart in it.
///
/// **First in the chain, ahead of the cohort matcher**, and the ordering is
/// load-bearing. "Average systolic BP by district" contains the words *BP* and
/// *district*, so the cohort matcher would take it as a free-text search and
/// return a list of patients whose notes mention them — an answer that is not
/// wrong so much as not the question. This parser declines anything that is
/// not clearly analytical (see the guards in [AnalysisParser.parse]: a bare
/// table name, a plain count, an unrecognised field all return null), so
/// running it first costs the cohort matcher nothing.
class AnalysisInterpreter implements Interpreter {
  const AnalysisInterpreter();

  @override
  bool canRead(AssistRequest request) => request.hasText;

  @override
  String get name => 'analysis';

  /// Null: this is coded logic, and the badge is reserved for answers a model
  /// actually touched.
  @override
  String? get modelName => null;

  @override
  Future<AssistIntent?> interpret(
    AssistRequest request,
    Preprocessed input,
  ) async {
    // Identifiers are restored first. Redaction exists to keep an MRN away
    // from a model; nothing here leaves the device, and a stripped number
    // would break "last 6 months".
    final text = Preprocessor.restore(input);
    final spec = AnalysisParser.parse(text, asOf: request.now);
    if (spec == null) return null;

    return AnalysisIntent(
      spec: spec,
      // High but never 1. The grammar is small and matching is exact, so a
      // spec that parsed is almost certainly the question asked — but the
      // fuzzy field match underneath it can pick a neighbouring column, and
      // the pipeline should prefer a later interpreter that is certain.
      confidence: 0.82,
      matched: <String>[
        '${spec.table.label} table',
        if (spec.measure != null) '${spec.measure!.label} measured',
        if (spec.dimension != null) 'grouped by ${spec.dimension!.label}',
        if (spec.against != null) 'against ${spec.against!.label}',
        '${spec.aggregate.label} applied',
      ],
    );
  }
}
