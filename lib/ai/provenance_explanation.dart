import '../clinical/explanations.dart';
import 'presentation.dart';
import 'provenance.dart';

/// Turns the stage trail into the app's standard explanation sheet.
///
/// An answer assembled by a pipeline needs more than "here are the filters".
/// When a number is wrong, the useful question is *which stage* was wrong —
/// the wording, the interpretation, the permission check or the query — and
/// this is what makes that answerable.
///
/// It lives beside the pipeline rather than in the widget layer because it is
/// a statement about the *answer*, not about how it is drawn: any surface that
/// renders a result — the bubble, the page, a future export — needs the same
/// merged explanation, and none of them should own it.
abstract final class ProvenanceExplanation {
  static MetricExplanation of(
    Provenance provenance,
    Presentation presentation,
  ) {
    final owned = presentation.explanation;

    return MetricExplanation(
      title: owned?.title ?? 'How this answer was reached',
      summary: owned?.summary ??
          'Each stage below did one job, and each can be wrong on its own.',
      method: <String>[
        ...?owned?.method,
        if (owned != null) '—',
        for (final step in provenance.steps)
          '${step.stage}: ${step.summary}'
              '${step.byModel == null ? '' : ' (by ${step.byModel})'}'
              '${step.detail == null ? '' : ' — ${step.detail}'}',
      ],
      derivation: owned?.derivation ?? const <ExplainRow>[],
      total: owned?.total,
      confidence: owned?.confidence ??
          (provenance.involvedModel
              ? ExplainConfidence.heuristic
              : ExplainConfidence.measured),
      source: owned?.source ??
          (provenance.involvedModel
              ? 'Interpreted by a model, then run as a hand-written query'
              : 'Hand-written matching and a hand-written query — no model '
                  'was involved'),
      caveat: owned?.caveat,
    );
  }
}
