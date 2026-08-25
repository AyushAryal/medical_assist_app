import '../analytics/period_parser.dart';
import '../assist_request.dart';
import '../intent.dart';
import '../interpreter.dart';
import '../preprocess.dart';

/// Recognises the question that is really several: "dashboard", "overview",
/// "how are we doing".
///
/// First in the chain because its vocabulary is tiny and unambiguous — no
/// other interpreter wants these words, and everything else declines them
/// into a free-text search, which is the one answer they must not get.
class OverviewInterpreter implements Interpreter {
  const OverviewInterpreter();

  static final RegExp _words = RegExp(
    r'\b(?:dashboard|overview|at a glance|how (?:are|is) (?:we|the clinic) '
    r'doing|clinic (?:report|summary)|monthly report)\b',
  );

  @override
  bool canRead(AssistRequest request) => request.hasText;

  @override
  String get name => 'overview';

  @override
  String? get modelName => null;

  @override
  Future<AssistIntent?> interpret(
    AssistRequest request,
    Preprocessed input,
  ) async {
    final text = Preprocessor.restore(input);
    if (!_words.hasMatch(text)) return null;

    final period = PeriodParser.take(text, request.now);
    return OverviewIntent(
      confidence: 0.9,
      periodFrom: period.from,
      periodTo: period.to,
    );
  }
}
