import '../assist_request.dart';
import '../intent.dart';
import '../interpreter.dart';
import '../preprocess.dart';

/// Recognises a request that points at one specific patient.
///
/// It reads nothing out of the words to *find* the patient — that was already
/// done, unambiguously, by the `\pat` smart phrase, which put an exact id on the
/// request. All this decides is *what about them*: a whole-record summary, or a
/// reading of how their observations are progressing. Because it only fires when
/// [AssistRequest.patientId] is set, it sits first in the chain and declines
/// instantly for every register-wide question.
class PatientInterpreter implements Interpreter {
  const PatientInterpreter();

  @override
  String get name => 'patient lookup';

  @override
  String? get modelName => null;

  @override
  bool canRead(AssistRequest request) => request.patientId != null;

  static final RegExp _progression = RegExp(
    r'progress|trend|improv|deteriorat|\bworse\b|\bbetter\b|over time|'
    r'how (?:is|are)|doing',
    caseSensitive: false,
  );

  @override
  Future<AssistIntent?> interpret(
    AssistRequest request,
    Preprocessed input,
  ) async {
    final id = request.patientId;
    if (id == null) return null;

    final asksProgression = _progression.hasMatch(input.normalised) ||
        _progression.hasMatch(request.text);
    return PatientSummaryIntent(
      patientId: id,
      mode: asksProgression
          ? PatientSummaryMode.progression
          : PatientSummaryMode.summary,
    );
  }
}
