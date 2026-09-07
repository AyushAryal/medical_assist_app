import 'package:medical_app/data/services/assist/language_model.dart';

/// A model that answers with whatever it was told to say — which is the
/// point: tests about the *system's* handling of model output need the bad
/// cases on demand, and a real model would only make them flaky.
class ScriptedModel implements LanguageModelEngine {
  ScriptedModel({
    this.rewrite,
    this.assignment,
    this.instructions,
    this.extraction,
    this.handoff,
  });

  final String? rewrite;

  /// The reworded spoken-handoff reply.
  final String? handoff;

  /// The raw JSON reply to an extraction request.
  final String? extraction;

  /// The raw reply to a sentence-assignment request, e.g.
  /// `'SUBJECTIVE: 1\nPLAN: 2'`.
  final String? assignment;

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
  Future<String?> assignSentencesToSections(
    List<String> numberedSentences,
  ) async {
    sawText = numberedSentences.join('\n');
    return assignment;
  }

  @override
  Future<LanguageModelDraft> plainLanguageInstructions(String plan) async {
    sawText = plan;
    return LanguageModelDraft(text: instructions ?? '', engineName: name);
  }

  @override
  Future<LanguageModelDraft> spokenHandoff(String structuredHandoff) async {
    sawText = structuredHandoff;
    return LanguageModelDraft(
      text: handoff ?? structuredHandoff,
      engineName: name,
    );
  }

  @override
  Future<LanguageModelDraft> spokenBrief(String structuredSummary) async {
    sawText = structuredSummary;
    return LanguageModelDraft(text: rewrite ?? structuredSummary, engineName: name);
  }

  @override
  Future<LanguageModelDraft> patientReminder(String reviewContext) async {
    sawText = reviewContext;
    return LanguageModelDraft(text: rewrite ?? reviewContext, engineName: name);
  }

  @override
  Future<LanguageModelDraft> triageTalkingPoints(String presentation) async {
    sawText = presentation;
    return LanguageModelDraft(text: rewrite ?? presentation, engineName: name);
  }

  @override
  Future<LanguageModelDraft> referralLetter(String record) async {
    sawText = record;
    return LanguageModelDraft(text: rewrite ?? record, engineName: name);
  }

  @override
  Future<LanguageModelDraft> explainPlainly(String data) async {
    sawText = data;
    return LanguageModelDraft(text: rewrite ?? data, engineName: name);
  }

  @override
  Future<LanguageModelDraft> caseloadReport(String figures) async {
    sawText = figures;
    return LanguageModelDraft(text: rewrite ?? figures, engineName: name);
  }

  @override
  Future<String?> extractValues(
    String description, {
    required List<String> fields,
  }) async {
    sawText = description;
    return extraction;
  }

  @override
  Future<void> dispose() async {}
}
