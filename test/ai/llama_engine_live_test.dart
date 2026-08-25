@Tags(<String>['live-model'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/assist_request.dart';
import 'package:medical_app/ai/intent.dart';
import 'package:medical_app/ai/interpreter.dart';
import 'package:medical_app/ai/interpreters/analysis_interpreter.dart';
import 'package:medical_app/ai/interpreters/model_interpreter.dart';
import 'package:medical_app/ai/interpreters/overview_interpreter.dart';
import 'package:medical_app/ai/interpreters/pattern_interpreter.dart';
import 'package:medical_app/ai/interpreters/rank_interpreter.dart';
import 'package:medical_app/ai/preprocess.dart';
import 'package:medical_app/ai/provenance.dart';
import 'package:medical_app/data/services/assist/llama_engine.dart';

/// Real inference through the real shim, on the host.
///
/// Tagged `live-model` and skipped unless both artefacts exist, because it
/// needs a 500 MB model file and half a minute of CPU — but it is the only
/// test that can catch what every mock cannot: a broken chat template, a
/// mis-linked shim, a model that ignores the instruction. Run with:
///
///   tool/build_llm_shim.sh
///   curl -L -o /tmp/qwen.gguf https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf
///   CLINICAL_LLM_LIB=.native/linux-x64/libclinical_llm.so \
///   CLINICAL_LLM_MODEL=/tmp/qwen.gguf \
///   flutter test --tags live-model test/ai/llama_engine_live_test.dart
void main() {
  final libraryPath = Platform.environment['CLINICAL_LLM_LIB'];
  final modelPath = Platform.environment['CLINICAL_LLM_MODEL'];
  final available = libraryPath != null &&
      modelPath != null &&
      File(libraryPath).existsSync() &&
      File(modelPath).existsSync();

  test(
    'the engine rewrites a colloquial request into the question bank',
    () async {
      final engine = LlamaEngine(
        modelPath: modelPath!,
        modelName: 'qwen2.5-0.5b-test',
        libraryPath: libraryPath,
        threads: Platform.numberOfProcessors,
      );
      addTearDown(engine.dispose);

      expect(await engine.isReady(), isTrue);

      final vocabulary = ModelInterpreter.vocabulary();
      final rewrite = await engine.rephraseAsKnownQuestion(
        'can you flag whichever of my patients look like they are '
        'going downhill',
        vocabulary: vocabulary,
      );

      expect(rewrite, isNotNull, reason: 'the model produced nothing');
      // The production gate, exactly: the rewrite must parse through the
      // coded grammars into a real intent. Verbatim bank membership is the
      // ideal, but a small model sometimes lands *near* the bank — "patients
      // with news2 above 5" for a bank entry phrased slightly differently —
      // and the system is safe either way because the grammars, not the
      // model, decide what runs. What must never pass is a rewrite the
      // grammars refuse.
      final request = AssistRequest(
        text: rewrite!.toLowerCase(),
        source: RequestSource.programmatic,
      );
      final probe = Provenance();
      final intent = await InterpreterChain(const <Interpreter>[
        OverviewInterpreter(),
        RankInterpreter(),
        AnalysisInterpreter(),
        PatternInterpreter(),
      ]).run(request, Preprocessor.run(request, probe), probe);
      expect(intent, isNot(isA<UnknownIntent>()),
          reason: 'the grammars must accept the rewrite: "$rewrite"');
      // And "going downhill" must land on risk, not on some other topic.
      expect(intent, anyOf(isA<RankIntent>(), isA<QueryIntent>()),
          reason: 'expected a risk-shaped intent for "$rewrite"');
    },
    skip: available ? false : 'set CLINICAL_LLM_LIB and CLINICAL_LLM_MODEL',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'an off-topic request is refused rather than force-fitted',
    () async {
      final engine = LlamaEngine(
        modelPath: modelPath!,
        modelName: 'qwen2.5-0.5b-test',
        libraryPath: libraryPath,
        threads: Platform.numberOfProcessors,
      );
      addTearDown(engine.dispose);

      final rewrite = await engine.rephraseAsKnownQuestion(
        'write me a poem about the sea',
        vocabulary: ModelInterpreter.vocabulary(),
      );
      // NONE → null is the honest outcome; a bank question would also be
      // "safe" but this asserts the model actually read the instruction.
      expect(rewrite, isNull, reason: 'got: "$rewrite"');
    },
    skip: available ? false : 'set CLINICAL_LLM_LIB and CLINICAL_LLM_MODEL',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
