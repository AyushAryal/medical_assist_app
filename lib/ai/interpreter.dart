import 'assist_request.dart';
import 'intent.dart';
import 'preprocess.dart';
import 'provenance.dart';

/// Turns a request into an intent, or declines.
///
/// Deliberately small. An interpreter does not touch the database, does not
/// know what a widget is, and cannot perform anything — it reads text and
/// returns a description of what was asked. That is what makes it possible to
/// have several, test each in isolation, and reason about which one answered.
abstract interface class Interpreter {
  /// Shown in the provenance trail.
  String get name;

  /// Whether this interpreter can read what the request is made of.
  ///
  /// Every interpreter today reads text, so every implementation returns
  /// [AssistRequest.hasText] — which looks like ceremony until the first
  /// non-text part arrives. An image interpreter will return true for a photo
  /// and false for a sentence, and the chain below already knows to skip
  /// rather than crash. The seam has to exist *before* the second input kind
  /// does, because retrofitting it means touching every interpreter at once.
  bool canRead(AssistRequest request);

  /// Null for coded logic. A model name here is what marks an answer as
  /// generated, everywhere downstream.
  String? get modelName;

  /// Returns null to pass to the next interpreter.
  Future<AssistIntent?> interpret(
    AssistRequest request,
    Preprocessed input,
  );
}

/// Runs interpreters in order and takes the first confident answer.
///
/// Order is the whole design, and it follows from a property of this
/// particular app: the schema is small and closed. Eleven tables and a fixed
/// clinical vocabulary means hand-written matching covers most of what anyone
/// will ask, and it does so instantly, offline, identically on every device,
/// and in a way that can be shown back and argued with.
///
/// So coded logic goes first, always. A model — if one is ever installed — is
/// the *fallback* for phrasings the patterns miss, not the engine. Inverting
/// that would trade something exact and free for something approximate and
/// expensive, on a problem where exactness is available.
///
/// The chain also degrades honestly: with no model installed, the last
/// interpreter simply declines and the user is told what was not understood,
/// rather than being handed a guess.
class InterpreterChain {
  const InterpreterChain(this.interpreters, {this.acceptThreshold = 0.25});

  final List<Interpreter> interpreters;

  /// Below this, an interpretation is not worth acting on and the chain moves
  /// on. A low-confidence answer that is *presented* as an answer is worse
  /// than no answer.
  final double acceptThreshold;

  Future<AssistIntent> run(
    AssistRequest request,
    Preprocessed input,
    Provenance provenance,
  ) async {
    final declined = <String>[];

    for (final interpreter in interpreters) {
      if (!interpreter.canRead(request)) {
        declined.add('${interpreter.name} (different kind of input)');
        continue;
      }
      final intent = await interpreter.interpret(request, input);
      if (intent == null || intent is UnknownIntent) {
        declined.add(interpreter.name);
        continue;
      }
      if (intent.confidence < acceptThreshold) {
        declined.add('${interpreter.name} (too unsure)');
        continue;
      }

      provenance.add(
        'interpret',
        'Understood by ${interpreter.name}',
        detail: intent.describe().join(' · '),
        confidence: intent.confidence,
        byModel: interpreter.modelName,
      );
      return intent;
    }

    provenance.add(
      'interpret',
      'Not understood',
      detail: declined.isEmpty
          ? null
          : 'Tried: ${declined.join(', ')}',
      confidence: 0,
    );
    return const UnknownIntent(
      reason: 'Nothing in that matched something searchable.',
    );
  }
}
