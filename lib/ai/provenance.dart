/// A record of how an answer was reached, stage by stage.
///
/// Every derived value in this app carries an explanation; an answer assembled
/// by a *pipeline* needs more than that. "14 patients" is the product of a
/// normalisation, an interpretation, an authorisation decision and a query, and
/// when it is wrong the useful question is *which stage* was wrong. Without a
/// trail the only available answer is "the AI got it wrong", which is not
/// something anyone can act on.
class ProvenanceStep {
  const ProvenanceStep({
    required this.stage,
    required this.summary,
    this.detail,
    this.confidence,
    this.byModel,
  });

  /// Which stage produced this — `preprocess`, `interpret`, `authorise`,
  /// `execute`, `present`.
  final String stage;

  /// One line, written for a clinician rather than a developer.
  final String summary;

  final String? detail;

  /// 0–1 where the stage has an opinion about its own reliability.
  final double? confidence;

  /// The model that did the work, if a model did. Null means coded logic —
  /// which on this schema is the common case and the preferable one.
  final String? byModel;

  bool get wasModel => byModel != null;
}

/// The whole trail.
class Provenance {
  Provenance();

  final List<ProvenanceStep> _steps = <ProvenanceStep>[];

  List<ProvenanceStep> get steps => List.unmodifiable(_steps);

  /// True when any stage used a model. Drives whether the answer is badged as
  /// generated — a purely deterministic answer should not be, because saying
  /// "AI" over a hand-written SQL query devalues the badge everywhere it
  /// genuinely matters.
  bool get involvedModel => _steps.any((step) => step.wasModel);

  void add(
    String stage,
    String summary, {
    String? detail,
    double? confidence,
    String? byModel,
  }) {
    _steps.add(
      ProvenanceStep(
        stage: stage,
        summary: summary,
        detail: detail,
        confidence: confidence,
        byModel: byModel,
      ),
    );
  }

  /// The lowest confidence any stage reported. An answer is only as trustworthy
  /// as its weakest step, and averaging would hide exactly the step worth
  /// knowing about.
  double? get weakestConfidence {
    final scored = _steps
        .map((step) => step.confidence)
        .whereType<double>()
        .toList();
    return scored.isEmpty
        ? null
        : scored.reduce((a, b) => a < b ? a : b);
  }
}
