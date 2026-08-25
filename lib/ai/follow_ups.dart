import 'cohort/cohort_query.dart';
import 'analytics/analysis.dart';
import 'intent.dart';
import 'interpreters/pattern_interpreter.dart';

/// A next question, offered as a button.
///
/// The label is what a person reads; [text] is what actually gets asked, and it
/// is a phrase the interpreter already answers. That distinction is the whole
/// value of these: a tap hands the pipeline an unambiguous request instead of
/// leaving it to infer one, and because the asked text is a real question, the
/// answer arrives with the same filters shown back and the same provenance as
/// if it had been typed. Nothing here is a private back channel into the
/// engine.
class FollowUp {
  const FollowUp({required this.label, required this.text});

  final String label;
  final String text;
}

/// What to offer after an answer.
///
/// Answers beget questions — a count invites "of whom?", a list invites "what
/// is the shape of that?" — and the person asking usually cannot guess which
/// of those this app can do. Offering the two or three that apply *to the
/// answer on screen* teaches the feature at the moment it is relevant, which
/// is the only moment anyone reads.
///
/// Every follow-up re-cuts the cohort that was just asked about rather than
/// starting fresh, so the numbers stay comparable.
class FollowUps {
  const FollowUps._();

  /// The re-cuts that make sense for each kind of record.
  ///
  /// Visit type only means something for visits; status is an appointment
  /// property. Offering a breakdown that would come back empty everywhere is
  /// worse than offering none, because the reader cannot tell an unsupported
  /// cut from a genuinely empty one.
  static const Map<QueryEntity, List<ReportKind>> _cuts =
      <QueryEntity, List<ReportKind>>{
    QueryEntity.patients: <ReportKind>[
      ReportKind.byAgeBand,
      ReportKind.bySex,
      ReportKind.activityOverTime,
    ],
    QueryEntity.appointments: <ReportKind>[
      ReportKind.byStatus,
      ReportKind.activityOverTime,
    ],
    QueryEntity.visits: <ReportKind>[
      ReportKind.byVisitType,
      ReportKind.activityOverTime,
      ReportKind.byAgeBand,
    ],
    QueryEntity.vitals: <ReportKind>[ReportKind.activityOverTime],
    QueryEntity.notes: <ReportKind>[ReportKind.activityOverTime],
    QueryEntity.files: <ReportKind>[ReportKind.activityOverTime],
  };

  static const int _limit = 3;

  /// The next moves on a chart.
  ///
  /// Different in kind from re-cutting a cohort: what someone wants after
  /// seeing a distribution is usually the same numbers seen another way — a
  /// finer grain, the median instead of the mean, the shares as a pie. Each is
  /// one word appended to the question they already asked, which keeps the two
  /// answers comparable and keeps the phrasing something they could have typed.
  static List<FollowUp> _afterAnalysis(String text, AnalysisSpec spec) {
    final base = text.trim();
    final out = <FollowUp>[];

    // A mean hides a skew, and clinical measurements skew. Offering the median
    // next to it is the cheapest way to make that visible.
    if (spec.aggregate == Aggregate.average) {
      out.add(FollowUp(label: 'Median', text: 'median $base'));
    } else if (spec.aggregate == Aggregate.median) {
      out.add(FollowUp(label: 'Mean', text: 'average $base'));
    }

    if (spec.isTimeline) {
      final coarser = switch (spec.bucket) {
        TimeBucket.day => TimeBucket.week,
        TimeBucket.week => TimeBucket.month,
        TimeBucket.month => TimeBucket.quarter,
        TimeBucket.quarter || TimeBucket.year => TimeBucket.year,
      };
      if (coarser != spec.bucket) {
        out.add(FollowUp(
          label: 'Per ${coarser.label}',
          text: '$base per ${coarser.label}',
        ));
      }
    } else if (spec.table.defaultTime != null) {
      out.add(FollowUp(label: 'Over time', text: '$base per month'));
    }

    // Only where the parts genuinely sum to the whole. A pie of averages
    // states something false about the total, so it is not offered.
    final partsSumToWhole = spec.aggregate == Aggregate.count ||
        spec.aggregate == Aggregate.sum;
    if (partsSumToWhole && !spec.isTimeline && spec.dimension != null &&
        spec.style != ChartStyle.pie) {
      out.add(FollowUp(label: 'As a pie', text: '$base as a pie chart'));
    }

    if (spec.measure != null && spec.dimension == null) {
      out.add(FollowUp(
        label: 'Spread',
        text: 'distribution of ${spec.measure!.label.toLowerCase()}',
      ));
    }

    return out.length > _limit ? out.sublist(0, _limit) : out;
  }

  /// After a ranking: the same people cut differently, or the shape behind
  /// the extremes. Built from the spec rather than the wording, because a
  /// ranking can arrive from words the re-phrase should not have to survive
  /// ("febrile kids" re-cut per week is not a sentence anyone can edit).
  static List<FollowUp> _afterRank(RankIntent intent) {
    final spec = intent.spec;
    final measure = spec.measure.synonyms.isEmpty
        ? spec.measure.label.toLowerCase()
        : spec.measure.synonyms.first;
    return <FollowUp>[
      // The extremes invite "how bad is the middle" — the histogram answers.
      FollowUp(label: 'Spread', text: 'distribution of $measure'),
      FollowUp(
        label: 'Average over time',
        text: 'average $measure per month',
      ),
      if (spec.limit < 25)
        FollowUp(
          label: 'Top ${spec.limit * 2}',
          text: 'top ${spec.limit * 2} patients by $measure',
        ),
    ];
  }

  static List<FollowUp> after({
    required String text,
    required AssistIntent intent,
  }) {
    // An analysis re-cuts along entirely different axes — the chart shape, the
    // grain of the timeline, which statistic — so it has its own set.
    if (intent is AnalysisIntent) return _afterAnalysis(text, intent.spec);
    if (intent is RankIntent) return _afterRank(intent);

    // A change waiting to be confirmed, or a question that was not understood.
    // Both already carry their own next step — accept it, or one of the
    // suggestions — and a row of unrelated chips would compete with it.

    final (CohortQuery? query, ReportKind? current) = switch (intent) {
      QueryIntent(:final query) => (query, null),
      ReportIntent(:final query, :final kind) => (query, kind),
      AnalysisIntent() ||
      RankIntent() ||
      OverviewIntent() ||
      MutationIntent() ||
      UnknownIntent() =>
        (null, null),
    };
    if (query == null) return const <FollowUp>[];

    // Without this, "visits per week by age band" accumulates every cut ever
    // tapped and stops meaning anything.
    final base = PatternInterpreter.withoutReportPhrase(text);
    if (base.isEmpty) return const <FollowUp>[];

    final out = <FollowUp>[
      // Back to the people. A chart says how many; acting on it means opening
      // a record, and losing the way back to the list is how a report becomes
      // a dead end.
      if (current != null)
        FollowUp(label: 'Show the list', text: base),
      for (final kind in _cuts[query.entity] ?? const <ReportKind>[])
        if (kind != current)
          FollowUp(
            label: kind.shortLabel,
            text: '$base ${kind.phrase}',
          ),
    ];

    return out.length > _limit ? out.sublist(0, _limit) : out;
  }
}
