import '../analytics/analysis.dart';
import '../cohort/cohort_query.dart';
import '../intent.dart';
import '../presentation.dart';
import '../provenance.dart';
import '../records/rank_spec.dart';
import '../schema/field_registry.dart';
import 'analysis_handler.dart';
import 'query_handler.dart';
import 'rank_handler.dart';

/// Answers "how is the clinic doing" as a dashboard.
///
/// This handler owns no computation. Each tile is a question the pipeline
/// already answers — a timeline, a breakdown, a ranking, a worklist — run
/// through the handler that owns it, so a fix to any of them fixes the
/// dashboard for free and the dashboard can never disagree with the same
/// question asked alone. Composition is the entire job.
///
/// The tile choice is opinionated on purpose: activity, attendance, risk and
/// unfinished work are the four things a clinic lead checks daily. A
/// configurable dashboard is a later feature; a useful one is this file.
class OverviewHandler {
  const OverviewHandler(this._analyses, this._ranks, this._queries);

  final AnalysisHandler _analyses;
  final RankHandler _ranks;
  final QueryHandler _queries;

  Future<Presentation> run(
    OverviewIntent intent,
    Provenance provenance, {
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    // Default window: the last 12 weeks — long enough for a trend, short
    // enough that this quarter's problem is not diluted by last year's.
    final from = intent.periodFrom ??
        now.subtract(const Duration(days: 7 * 12));
    final to = intent.periodTo;

    final panels = <({String title, Presentation body})>[
      (
        title: 'Visits per week',
        body: await _analyses.run(
          AnalysisIntent(
            spec: AnalysisSpec(
              table: FieldRegistry.encounters,
              aggregate: Aggregate.count,
              dimension: FieldRegistry.encounters.defaultTime,
              dimensionTable: FieldRegistry.encounters,
              periodFrom: from,
              periodTo: to,
            ),
            confidence: 1,
          ),
          provenance,
        ),
      ),
      (
        title: 'Appointments by outcome',
        body: await _analyses.run(
          AnalysisIntent(
            spec: AnalysisSpec(
              table: FieldRegistry.appointments,
              aggregate: Aggregate.count,
              dimension: FieldRegistry.appointments.field('status'),
              dimensionTable: FieldRegistry.appointments,
              periodFrom: from,
              periodTo: to,
            ),
            confidence: 1,
          ),
          provenance,
        ),
      ),
      (
        title: 'Highest early-warning scores',
        body: await _ranks.run(
          RankIntent(
            spec: RankSpec(
              table: FieldRegistry.vitals,
              measure: FieldRegistry.vitals.field('news2_score')!,
              descending: true,
              limit: 5,
              periodFrom: from,
              periodTo: to,
            ),
            confidence: 1,
          ),
          provenance,
        ),
      ),
      (
        title: 'Unfinished notes',
        body: await _queries.run(
          const QueryIntent(
            query: CohortQuery(
              kind: CohortQueryKind.cohort,
              entity: QueryEntity.notes,
              noteStatus: 'draft',
            ),
            confidence: 1,
          ),
          provenance,
          rowLimit: 5,
        ),
      ),
    ];

    provenance.add(
      'present',
      'Composed ${panels.length} panels',
      detail: 'Each panel is the same answer the question would get asked '
          'alone, so the dashboard cannot disagree with a direct question.',
    );

    return DashboardPresentation(
      headline: 'The clinic at a glance — activity, attendance, risk and '
          'unfinished work.',
      panels: panels,
    );
  }
}
