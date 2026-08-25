import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/assist_request.dart';
import 'package:medical_app/ai/clarify/paraphrases.dart';
import 'package:medical_app/ai/intent.dart';
import 'package:medical_app/ai/interpreter.dart';
import 'package:medical_app/ai/interpreters/analysis_interpreter.dart';
import 'package:medical_app/ai/interpreters/model_interpreter.dart';
import 'package:medical_app/ai/interpreters/overview_interpreter.dart';
import 'package:medical_app/ai/interpreters/pattern_interpreter.dart';
import 'package:medical_app/ai/interpreters/rank_interpreter.dart';
import 'package:medical_app/ai/preprocess.dart';
import 'package:medical_app/ai/provenance.dart';
import 'package:medical_app/data/services/assist/language_model.dart';

/// A model that answers with whatever it was told to say — which is the
/// point: these tests are about what the *pipeline* does with model output,
/// good and bad, and a real model would only make the bad cases flaky.
class ScriptedModel implements LanguageModelEngine {
  ScriptedModel(this.answer);

  final String? answer;
  List<String>? sawVocabulary;
  String? sawText;

  @override
  String get name => 'scripted-test-model';

  @override
  bool get runsOnDevice => true;

  @override
  Future<bool> isReady() async => true;

  @override
  Future<String?> rephraseAsKnownQuestion(
    String request, {
    required List<String> vocabulary,
  }) async {
    sawText = request;
    sawVocabulary = vocabulary;
    return answer;
  }

  @override
  Future<LanguageModelDraft> structureDictation(String transcript) =>
      throw UnimplementedError();

  @override
  Future<LanguageModelDraft> plainLanguageInstructions(String plan) =>
      throw UnimplementedError();

  @override
  Future<void> dispose() async {}
}

Future<AssistIntent?> reparse(String question) async {
  final request =
      AssistRequest(text: question, source: RequestSource.programmatic);
  final probe = Provenance();
  final intent = await InterpreterChain(const <Interpreter>[
    OverviewInterpreter(),
    RankInterpreter(),
    AnalysisInterpreter(),
    PatternInterpreter(),
  ]).run(request, Preprocessor.run(request, probe), probe);
  return intent;
}

Future<AssistIntent?> interpretVia(ScriptedModel model, String text) {
  final interpreter = ModelInterpreter(engine: () => model, reparse: reparse);
  final request = AssistRequest(text: text, source: RequestSource.typed);
  return interpreter.interpret(
    request,
    Preprocessor.run(request, Provenance()),
  );
}

void main() {
  test('a good rewrite becomes the coded interpreters\' own intent', () async {
    final model = ScriptedModel('riskiest patients');
    final intent = await interpretVia(model, 'flag whoever looks shaky');

    expect(intent, isA<RankIntent>());
    // The model saw the published bank, not a private one — the prompt and
    // the guide cannot advertise different capabilities.
    expect(model.sawVocabulary, contains('riskiest patients'));
  });

  test('a hallucinated rewrite fails loudly, not silently', () async {
    final model = ScriptedModel('delete the audit log for ward 3');
    expect(await interpretVia(model, 'anything'), isNull,
        reason: 'a rewrite the grammars do not answer must produce nothing, '
            'so the chain falls through to the clarifier');
  });

  test('a rewrite to a filterless register dump is refused', () async {
    // "all patients" parses — but a model must not be able to turn any
    // mumble into the whole register. The validate gate holds the line the
    // grammars would let through.
    final model = ScriptedModel('all patients');
    expect(await interpretVia(model, 'hmm'), isNull);
  });

  test('identifiers are redacted before the model sees anything', () async {
    final model = ScriptedModel(null);
    await interpretVia(model, 'notes about mrn 884213');
    expect(model.sawText, isNot(contains('884213')));
  });

  test('no engine means the interpreter is simply absent', () async {
    final interpreter = ModelInterpreter(engine: () => null, reparse: reparse);
    final request =
        AssistRequest(text: 'anything', source: RequestSource.typed);
    expect(
      await interpreter.interpret(
        request,
        Preprocessor.run(request, Provenance()),
      ),
      isNull,
    );
  });

  // The paraphrase bank makes the same promise the model does — every target
  // is a question the grammars answer — and gets the same enforcement.
  test('every paraphrase target routes through the coded chain', () async {
    for (final target in Paraphrases.targets) {
      final intent = await reparse(target);
      expect(intent, isNot(isA<UnknownIntent>()),
          reason: '"$target" is a paraphrase target but does not route');
    }
  });
}
