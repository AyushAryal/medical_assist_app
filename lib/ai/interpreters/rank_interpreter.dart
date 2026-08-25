import '../assist_request.dart';
import '../intent.dart';
import '../interpreter.dart';
import '../preprocess.dart';
import '../records/rank_parser.dart';

/// Recognises "who stands out" questions — superlatives, screening
/// qualifiers, thresholds.
///
/// Runs **before** the analysis interpreter because the two overlap at one
/// word: "highest". "Highest BMI" is a maximum and belongs to analysis;
/// "patients with the highest BMI" is a *who* and belongs here. The rank
/// parser only claims when a person is in the sentence (or an explicit
/// "top N" is), so the ordering costs analysis nothing — see the guards in
/// [RankParser.parse].
class RankInterpreter implements Interpreter {
  const RankInterpreter();

  @override
  bool canRead(AssistRequest request) => request.hasText;

  @override
  String get name => 'ranking';

  /// Coded logic; the badge stays reserved for answers a model touched.
  @override
  String? get modelName => null;

  @override
  Future<AssistIntent?> interpret(
    AssistRequest request,
    Preprocessed input,
  ) async {
    final spec = RankParser.parse(
      Preprocessor.restore(input),
      asOf: request.now,
    );
    if (spec == null) return null;

    return RankIntent(
      spec: spec,
      // Matching is exact-word against a closed list, but the fuzzy field
      // resolution underneath can land on a neighbouring column — same
      // reasoning as the analysis interpreter.
      confidence: 0.85,
      matched: <String>[
        '${spec.measure.label} measured',
        spec.describe(),
      ],
    );
  }
}
