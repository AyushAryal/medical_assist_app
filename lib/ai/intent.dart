import 'cohort/cohort_query.dart';
import 'analytics/analysis.dart';
import 'records/rank_spec.dart';
import 'schema/field_registry.dart';

/// What the assistant understood a request to be asking for.
///
/// The pivot of the whole pipeline. Everything upstream — pattern matching
/// today, a small model tomorrow — produces one of these, and everything
/// downstream consumes them. Two properties follow from that and both are the
/// point:
///
/// * **No interpreter ever produces SQL, a widget, or a database call.** It
///   produces a description of what was asked. A wrong intent is visible,
///   because the intent is shown back; a wrong query is not.
/// * **Adding an output kind is adding a case here and a handler**, not
///   threading a new path through the UI. A record, a report, a change to the
///   register and a plain answer are all intents.
sealed class AssistIntent {
  const AssistIntent();

  /// How sure the interpreter was, 0–1.
  double get confidence;

  /// The filters or parameters, in clinical English, for showing back.
  List<String> describe();
}

/// Read the register: counts, lists, recall, overdue, cohorts.
class QueryIntent extends AssistIntent {
  const QueryIntent({
    required this.query,
    required this.confidence,
    this.matched = const <String>[],
    this.projection = const <DataField>[],
    this.preferTable = false,
  });

  /// True where the wording asked for a table outright — "as a table".
  final bool preferTable;

  final CohortQuery query;

  @override
  final double confidence;

  /// What in the request produced each filter.
  final List<String> matched;

  /// Fields to show as columns beside each person — the "and their contact
  /// numbers" part of a question. Never a filter: projecting a field changes
  /// what the table shows, not who is on it, and conflating the two is how a
  /// directory request silently becomes a cohort.
  final List<DataField> projection;

  @override
  List<String> describe() => <String>[
        ...query.describe(),
        if (projection.isNotEmpty)
          'showing ${projection.map((f) => f.label.toLowerCase()).join(', ')}',
      ];
}

/// Aggregate something into a shape worth looking at — a trend over weeks, a
/// breakdown by category.
///
/// Separate from [QueryIntent] because the *question* is different: a query
/// asks "who", a report asks "how is this distributed". Answering the second
/// with a list is what makes reporting features unusable.
class ReportIntent extends AssistIntent {
  const ReportIntent({
    required this.kind,
    required this.query,
    required this.confidence,
    this.matched = const <String>[],
  });

  final ReportKind kind;
  final CohortQuery query;

  @override
  final double confidence;

  final List<String> matched;

  @override
  List<String> describe() => <String>[kind.label, ...query.describe()];
}

enum ReportKind { activityOverTime, byAgeBand, bySex, byVisitType, byStatus }

extension ReportKindX on ReportKind {
  String get label => switch (this) {
        ReportKind.activityOverTime => 'Activity over time',
        ReportKind.byAgeBand => 'Broken down by age band',
        ReportKind.bySex => 'Broken down by sex at birth',
        ReportKind.byVisitType => 'Broken down by visit type',
        ReportKind.byStatus => 'Broken down by status',
      };

  /// The same thing on a button, where there is room for three words.
  String get shortLabel => switch (this) {
        ReportKind.activityOverTime => 'Per week',
        ReportKind.byAgeBand => 'By age',
        ReportKind.bySex => 'By sex',
        ReportKind.byVisitType => 'By visit type',
        ReportKind.byStatus => 'By status',
      };

  /// The words that ask for this cut.
  ///
  /// A follow-up button appends this to what was already asked, so it has to
  /// be a phrase the interpreter recognises — otherwise the button is one that
  /// quietly does nothing. The regexes in `PatternInterpreter.reportPatterns`
  /// are the other half of that contract, and a test holds the two together.
  String get phrase => switch (this) {
        ReportKind.activityOverTime => 'per week',
        ReportKind.byAgeBand => 'by age band',
        ReportKind.bySex => 'by sex',
        ReportKind.byVisitType => 'by visit type',
        ReportKind.byStatus => 'by status',
      };
}

/// Aggregate an arbitrary field of an arbitrary table into a chart.
///
/// The general case that [ReportIntent] is the clinical special case of.
/// [ReportIntent] re-uses the hand-written cohort filters, which is what makes
/// "diabetics per week" trustworthy; this one reaches any column the schema
/// registry describes, which is what makes "average waiting time by clinician"
/// possible at all. Both exist because neither subsumes the other: the first
/// has clinical definitions baked in, the second has reach.
class AnalysisIntent extends AssistIntent {
  const AnalysisIntent({
    required this.spec,
    required this.confidence,
    this.matched = const <String>[],
  });

  final AnalysisSpec spec;

  @override
  final double confidence;

  /// What in the request produced the table, the field and the aggregate.
  final List<String> matched;

  @override
  List<String> describe() => <String>[
        spec.describe(),
        if (spec.periodFrom != null || spec.periodTo != null)
          'within the requested period',
      ];
}

/// Pick people out by a measured value — ranked, thresholded, or both.
///
/// The third question shape. A cohort asks "who matches these filters", an
/// analysis asks "what is the aggregate shape"; this asks "*who stands out*".
/// "Riskiest patients", "patients with high BP" and "top ten by BMI" are all
/// this intent with different [RankSpec] fields.
class RankIntent extends AssistIntent {
  const RankIntent({
    required this.spec,
    required this.confidence,
    this.matched = const <String>[],
  });

  final RankSpec spec;

  @override
  final double confidence;

  final List<String> matched;

  @override
  List<String> describe() => <String>[
        'Ranked ${spec.table.label}',
        spec.describe(),
        if (spec.periodFrom != null) 'within the requested period',
      ];
}

/// The question that is really several questions: "how is the clinic doing".
///
/// Answered as a dashboard of ordinary answers, each produced by an ordinary
/// handler, so every tile keeps the guarantees a lone answer has — its own
/// explanation, its own caveats, its own honest emptiness.
class OverviewIntent extends AssistIntent {
  const OverviewIntent({
    required this.confidence,
    this.periodFrom,
    this.periodTo,
  });

  final DateTime? periodFrom;
  final DateTime? periodTo;

  @override
  final double confidence;

  @override
  List<String> describe() => <String>[
        'Clinic overview',
        if (periodFrom != null) 'for the requested period',
      ];
}

/// A change to the record, described but **not performed**.
///
/// Mutations arrive as proposals and stay proposals until a person accepts
/// one. That is not caution for its own sake: a misread question that runs a
/// read query wastes a moment, and a misread question that writes to a chart
/// puts something in a medical record that nobody said. The two failures are
/// not comparable, so they do not get the same path.
///
/// Nothing in this app executes one of these from language alone.
class MutationIntent extends AssistIntent {
  const MutationIntent({
    required this.operation,
    required this.entity,
    required this.summary,
    required this.confidence,
    this.patientId,
    this.fields = const <String, String>{},
  });

  final MutationOperation operation;
  final QueryEntity entity;

  /// One sentence describing the change, for the confirmation prompt.
  final String summary;

  final String? patientId;
  final Map<String, String> fields;

  @override
  final double confidence;

  @override
  List<String> describe() => <String>[
        summary,
        for (final entry in fields.entries) '${entry.key}: ${entry.value}',
      ];
}

enum MutationOperation { create, update, archive }

extension MutationOperationX on MutationOperation {
  String get label => switch (this) {
        MutationOperation.create => 'Add',
        MutationOperation.update => 'Change',
        MutationOperation.archive => 'Archive',
      };
}

/// Show one patient, whole: their record gathered into a summary, or their
/// observations read as a progression.
///
/// Distinct from every other intent because it is *about a person, not the
/// register*. It only ever arises when the request carries an exact
/// [patientId] — resolved by the `\pat` smart phrase — so there is no name to
/// mis-resolve and nothing here is generated: the summary is assembled from the
/// record by a handler, the same way a chart screen is.
class PatientSummaryIntent extends AssistIntent {
  const PatientSummaryIntent({
    required this.patientId,
    this.mode = PatientSummaryMode.summary,
    this.confidence = 0.97,
  });

  final String patientId;
  final PatientSummaryMode mode;

  @override
  final double confidence;

  @override
  List<String> describe() => <String>[
        switch (mode) {
          PatientSummaryMode.summary => 'Patient summary',
          PatientSummaryMode.progression => 'How the patient is progressing',
        },
      ];
}

enum PatientSummaryMode { summary, progression }

/// Nothing was understood well enough to act on.
///
/// A first-class intent rather than a null, so the pipeline has one shape of
/// answer and the reason travels with it. "I did not understand" is a result;
/// it needs provenance too.
class UnknownIntent extends AssistIntent {
  const UnknownIntent({
    required this.reason,
    this.suggestions = const <String>[],
  });

  final String reason;
  final List<String> suggestions;

  @override
  double get confidence => 0;

  @override
  List<String> describe() => <String>[reason];
}
