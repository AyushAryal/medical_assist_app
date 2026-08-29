import 'package:flutter/services.dart';

import 'language_model.dart';

/// The system on-device language model (Apple Intelligence), reached over a
/// method channel to the Foundation Models framework.
///
/// Same contract as every other engine — rewriting only, never authorship — but
/// no download and no bundled weights: it uses the model the OS already ships.
/// Preferred on capable Apple hardware; elsewhere (or when the user has not
/// enabled Apple Intelligence) [isReady] is false and the app falls back to a
/// downloaded model. Never in the critical path.
class AppleFoundationLanguageModel implements LanguageModelEngine {
  static const MethodChannel _channel =
      MethodChannel('app.medical/foundation_model');

  @override
  String get name => 'Apple Intelligence';

  @override
  bool get runsOnDevice => true;

  @override
  Future<bool> isReady() async {
    try {
      return await _channel.invokeMethod<String>('availability') == 'available';
    } on Object {
      // No channel (non-Apple), or the framework is absent — not an error.
      return false;
    }
  }

  /// Sends one instruction + input to the system model. Returns null on any
  /// failure, matching the rest of the contract: a null keeps the caller's
  /// deterministic fallback rather than surfacing an error.
  Future<String?> _complete(String instruction, String input) async {
    try {
      final reply = await _channel.invokeMethod<String>('generate', {
        'prompt': '$instruction\n\n$input',
      });
      final text = reply?.trim();
      return (text == null || text.isEmpty) ? null : text;
    } on Object {
      return null;
    }
  }

  LanguageModelDraft _draft(String text) =>
      LanguageModelDraft(text: text, engineName: name);

  @override
  Future<LanguageModelDraft> plainLanguageInstructions(String plan) async {
    final answer = await _complete(
      'Rewrite this clinical plan as short instructions the patient can '
      'follow at home, in plain words. Keep every instruction; add none.',
      plan,
    );
    return _draft(answer ?? plan);
  }

  @override
  Future<LanguageModelDraft> spokenHandoff(String structuredHandoff) async {
    final answer = await _complete(
      'Rewrite this SBAR handoff as one short, natural paragraph a clinician '
      'could read aloud at a shift change. Keep every fact and add none; '
      'invent nothing. Where a line says something is "not recorded", say so.',
      structuredHandoff,
    );
    return _draft(answer ?? structuredHandoff);
  }

  @override
  Future<LanguageModelDraft> spokenBrief(String structuredSummary) async {
    final answer = await _complete(
      'Rewrite this patient summary as one short, natural paragraph to hear '
      'before a consultation. Keep every fact and add none; where a line says '
      'something is "not recorded", say so.',
      structuredSummary,
    );
    return _draft(answer ?? structuredSummary);
  }

  @override
  Future<LanguageModelDraft> patientReminder(String reviewContext) async {
    final answer = await _complete(
      'Write a short, warm, plain-language appointment reminder for a patient '
      'whose review is due, using only the facts given. No medical advice, no '
      'new facts, no diagnosis — just a friendly reminder to book.',
      reviewContext,
    );
    return _draft(answer ?? reviewContext);
  }

  @override
  Future<LanguageModelDraft> triageTalkingPoints(String presentation) async {
    final answer = await _complete(
      'List 3 to 5 focused questions or examination points a clinician might '
      'consider for this presentation. These are prompts to consider, not a '
      'diagnosis and not instructions. Add no new facts. One per line.',
      presentation,
    );
    return _draft(answer ?? '');
  }

  @override
  Future<LanguageModelDraft> referralLetter(String record) async {
    final answer = await _complete(
      'Write a concise referral letter from these patient details: a brief '
      'opening, the reason for referral, relevant history, current medications '
      'and allergies, and the latest observations. Use only the facts given; '
      'add none; do not diagnose.',
      record,
    );
    return _draft(answer ?? record);
  }

  @override
  Future<LanguageModelDraft> explainPlainly(String data) async {
    final answer = await _complete(
      'Explain what these clinical values show, in plain language a patient '
      'could follow. Describe the numbers and their direction only. Do not '
      'diagnose, do not advise, and add no facts.',
      data,
    );
    return _draft(answer ?? data);
  }

  @override
  Future<LanguageModelDraft> caseloadReport(String figures) async {
    final answer = await _complete(
      'Write a short, plain-language brief of the clinic\'s day from these '
      'figures. State the numbers and what stands out. Add no facts, no '
      'advice, no diagnosis.',
      figures,
    );
    return _draft(answer ?? figures);
  }

  @override
  Future<String?> assignSentencesToSections(List<String> numberedSentences) {
    return _complete(
      'For each numbered sentence, say which SOAP section it belongs to '
      '(SUBJECTIVE, OBJECTIVE, ASSESSMENT, PLAN). Reply with lines like '
      '"PLAN: 3". Do not rewrite the sentences.',
      numberedSentences.join('\n'),
    );
  }

  @override
  Future<String?> rephraseAsKnownQuestion(
    String request, {
    required List<String> vocabulary,
  }) {
    return _complete(
      'Rewrite the request as the closest matching question from this list, '
      'copied exactly. Reply NONE if none fits.\n${vocabulary.join('\n')}',
      request,
    );
  }

  @override
  Future<String?> extractValues(
    String description, {
    required List<String> fields,
  }) {
    return _complete(
      'Extract these fields as a JSON object of field to value from the '
      'description. Fields: ${fields.join(', ')}. Reply with JSON only.',
      description,
    );
  }

  @override
  Future<void> dispose() async {}
}
