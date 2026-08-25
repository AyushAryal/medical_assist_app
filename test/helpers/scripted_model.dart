import 'package:medical_app/data/services/assist/language_model.dart';

/// A model that answers with whatever it was told to say — which is the
/// point: tests about the *system's* handling of model output need the bad
/// cases on demand, and a real model would only make them flaky.
class ScriptedModel implements LanguageModelEngine {
  ScriptedModel({this.rewrite, this.soap, this.instructions});

  final String? rewrite;
  final Map<String, String>? soap;
  final String? instructions;

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
    return rewrite;
  }

  @override
  Future<LanguageModelDraft> structureDictation(String transcript) async {
    sawText = transcript;
    return LanguageModelDraft(
      text: transcript,
      engineName: name,
      sections: soap ?? const <String, String>{},
    );
  }

  @override
  Future<LanguageModelDraft> plainLanguageInstructions(String plan) async {
    sawText = plan;
    return LanguageModelDraft(text: instructions ?? '', engineName: name);
  }

  @override
  Future<void> dispose() async {}
}
