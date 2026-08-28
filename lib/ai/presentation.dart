import '../clinical/explanations.dart';
import '../data/dao/cohort_dao.dart';
import 'analytics/analysis.dart';
import 'analytics/statistics.dart';

/// A way an answer can be shown.
///
/// Distinct from what the answer *is*. A ranked cohort is one answer that can
/// be read as tappable people, as a table with the measured column, or as a
/// bar chart of the values — same data, three renderings. Keeping the choice
/// out of the handlers means a handler decides *content* once, declares which
/// renderings are honest for it, and the person reading gets a toggle instead
/// of a re-query.
enum ResultView { list, table, chart }

/// What the assistant produced, as data rather than as widgets.
///
/// The reason this is a type and not a pile of nullable fields on a result
/// object: the set of things an answer can *be* is open and growing — a
/// number, a list of people, a chart, a document, a change waiting to be
/// confirmed — and every one of them needs to be testable without a widget
/// tree and renderable in more than one place. The bubble and the full page
/// already drifted apart twice when the shape of an answer lived in the UI.
///
/// Rendering is a `switch` over these in one widget. Adding a kind is adding a
/// case, and the compiler finds every place that has to change.
sealed class Presentation {
  const Presentation();

  /// How this reads in one line — the assistant's spoken answer.
  String get headline;

  /// Where the number or the rows came from.
  MetricExplanation? get explanation;

  /// Every rendering that is honest for this answer, best first.
  ///
  /// The first entry is what renders when nobody expressed a preference; the
  /// rest appear as a toggle. One entry means no toggle — offering a "chart"
  /// button on an answer that cannot honestly be charted is a button that
  /// lies.
  List<ResultView> get views => const <ResultView>[ResultView.list];
}

/// A single number, with what it counted.
class MetricPresentation extends Presentation {
  const MetricPresentation({
    required this.value,
    required this.label,
    required this.headline,
    this.explanation,
    this.rows = const <CohortRow>[],
    this.total,
    this.columns = const <String>[],
    this.cells = const <List<String>>[],
    this.preferTable = false,
  });

  final int value;

  /// What the number is of — "appointments", "patients".
  final String label;

  @override
  final String headline;

  @override
  final MetricExplanation? explanation;

  /// The records behind the number.
  ///
  /// Never optional in practice. A count with nothing to open is a dead end:
  /// the number is only useful if it can be acted on, and acting on it means
  /// opening a record.
  final List<CohortRow> rows;

  /// The true total, when [rows] is capped for display. A truncated list must
  /// never be mistaken for a complete one.
  final int? total;

  /// Extra columns beyond the person, for the table view — the projection a
  /// question like "patients and their contact numbers" asked for, or the
  /// measured value a ranking sorted by.
  final List<String> columns;

  /// One list of cells per entry in [rows], aligned by index, one cell per
  /// entry in [columns]. Kept as strings because by this point every value has
  /// been formatted once, kind-aware, by the field that owns it — the renderer
  /// must not get a second chance to format the same number differently.
  final List<List<String>> cells;

  /// True where the question itself asked for columns — "and their phone
  /// numbers", "as a table". The list of tappable people is otherwise the
  /// better default, because a row that opens the chart is worth more than a
  /// row that states a value.
  final bool preferTable;

  @override
  List<ResultView> get views => <ResultView>[
        if (preferTable && cells.isNotEmpty) ...<ResultView>[
          ResultView.table,
          ResultView.list,
        ] else ...<ResultView>[
          ResultView.list,
          if (cells.isNotEmpty) ResultView.table,
        ],
      ];
}

/// A series worth seeing the shape of.
///
/// Separate from a table because the question is different: a table answers
/// "what are the values", a chart answers "what is the shape". Answering the
/// second with a table is how reporting features go unread.
///
/// Carries its own statistics rather than leaving the reader to eyeball them.
/// A bar chart shows which category is biggest; it does not show that the
/// spread is so wide the ordering is noise, or that four fifths of the rows
/// had nothing recorded. Those belong next to the picture, not behind it.
class ChartPresentation extends Presentation {
  const ChartPresentation({
    required this.style,
    required this.points,
    required this.headline,
    required this.caption,
    this.valueLabel,
    this.axisLabel,
    this.unit,
    this.stats,
    this.correlation,
    this.trend,
    this.explanation,
    this.footnotes = const <String>[],
    this.preferTable = false,
  });

  /// How to draw it. Chosen from the shape of the data by
  /// [AnalysisSpec.styleFor] unless the question named a chart.
  final ChartStyle style;

  /// In the order they should be drawn. Ordering is the caller's decision —
  /// chronological for a trend, descending for a breakdown — because only the
  /// caller knows which the reader is looking for.
  final List<ChartPoint> points;

  @override
  final String headline;

  final String caption;

  /// What the value axis measures: "Average systolic BP".
  final String? valueLabel;

  /// What the category axis is: "District".
  final String? axisLabel;

  final String? unit;

  final Stats? stats;
  final Correlation? correlation;
  final Trend? trend;

  /// Things a reader has to know before believing the chart — folded groups,
  /// unrecorded rows, a part-finished final period.
  final List<String> footnotes;

  @override
  final MetricExplanation? explanation;

  /// True where the question named a table — "visits by clinician as a
  /// table". The data is computed identically; only the first rendering
  /// changes.
  final bool preferTable;

  @override
  List<ResultView> get views => <ResultView>[
        if (preferTable) ...<ResultView>[
          ResultView.table,
          ResultView.chart,
        ] else ...<ResultView>[
          ResultView.chart,
          // A scatter's table is a thousand unlabelled coordinate pairs —
          // nothing a person can read. Every other shape tabulates honestly.
          if (style != ChartStyle.scatter) ResultView.table,
        ],
      ];

  double get total => points.fold<double>(
        0,
        (sum, point) => point.value.isNaN ? sum : sum + point.value,
      );

  bool get isEmpty =>
      points.isEmpty || points.every((p) => p.value == 0 || p.value.isNaN);
}

/// Rows and columns, for something a chart would flatten.
class TablePresentation extends Presentation {
  const TablePresentation({
    required this.columns,
    required this.rows,
    required this.headline,
    this.explanation,
  });

  final List<String> columns;
  final List<List<String>> rows;

  @override
  final String headline;

  @override
  final MetricExplanation? explanation;

  @override
  List<ResultView> get views => const <ResultView>[ResultView.table];
}

/// Records found in prose rather than by a filter.
class MentionsPresentation extends Presentation {
  const MentionsPresentation({
    required this.mentions,
    required this.terms,
    required this.headline,
    this.explanation,
  });

  final List<TextMention> mentions;
  final List<String> terms;

  @override
  final String headline;

  @override
  final MetricExplanation? explanation;
}

/// A change waiting for a person to accept it.
///
/// Carries everything needed to show what would happen and nothing that would
/// make it happen. The pipeline cannot execute one of these; only a confirmed
/// action in the UI can, and that goes through the repository like any other
/// write, so it is audited identically. There is no second-class path into a
/// medical record.
class ProposalPresentation extends Presentation {
  const ProposalPresentation({
    required this.headline,
    required this.changes,
    required this.confirmLabel,
    this.blockedReason,
    this.explanation,
  });

  /// Field-by-field, what would change.
  final List<({String field, String from, String to})> changes;

  final String confirmLabel;

  /// Set when the actor is not permitted. The proposal is still shown — hiding
  /// it would leave someone wondering whether the app understood them — but it
  /// cannot be accepted, and it says why.
  final String? blockedReason;

  @override
  final String headline;

  @override
  final MetricExplanation? explanation;

  bool get isBlocked => blockedReason != null;
}

/// Several answers on one canvas.
///
/// For the question that is really six questions — "how is the clinic doing",
/// "monthly report" — where any single chart would answer a fraction and
/// imply it was the whole. Each panel is an ordinary [Presentation] produced
/// by an ordinary handler, so everything a single answer guarantees (its own
/// explanation, its own caveats, its own honest emptiness) holds for every
/// tile, and a new kind of panel is free the day its presentation exists.
class DashboardPresentation extends Presentation {
  const DashboardPresentation({
    required this.headline,
    required this.panels,
    this.explanation,
  });

  final List<({String title, Presentation body})> panels;

  @override
  final String headline;

  @override
  final MetricExplanation? explanation;
}

/// A question asked back.
///
/// The assistant's side of a dialogue: when a request is ambiguous or half
/// understood, this asks one targeted question, and every option on it is a
/// complete question the app provably answers — so answering is one tap and
/// the repair work stays on this side of the screen. Options *run* when
/// tapped, unlike suggestions, because they are answers to a question the
/// assistant itself just asked.
class ClarifyPresentation extends Presentation {
  const ClarifyPresentation({
    required this.headline,
    required this.options,
    this.explanation,
  });

  /// Label beside the full question it stands for.
  final List<({String label, String question})> options;

  @override
  final String headline;

  @override
  final MetricExplanation? explanation;
}

/// Nothing to show, and what to try instead.
class MessagePresentation extends Presentation {
  const MessagePresentation({
    required this.headline,
    this.suggestions = const <String>[],
    this.explanation,
  });

  final List<String> suggestions;

  @override
  final String headline;

  @override
  final MetricExplanation? explanation;
}

/// One patient, gathered from the record into a readable whole.
///
/// Every field here is already-formatted text, assembled by
/// `PatientSummaryHandler` straight from the chart — no model, nothing
/// generated. That is the point: a summary of a medical record has to *be* the
/// record, rearranged, never a paraphrase of it. Carried as strings so this
/// layer stays free of the data models, exactly like the other presentations.
class PatientSummaryPresentation extends Presentation {
  const PatientSummaryPresentation({
    required this.headline,
    required this.patientId,
    required this.identityLine,
    this.progression = false,
    this.allergyLine,
    this.problems = const <String>[],
    this.medications = const <String>[],
    this.vitals = const <({String label, String value})>[],
    this.news2Line,
    this.trends = const <String>[],
    this.visits = const <({String when, String summary})>[],
    this.upcoming = const <String>[],
    this.explanation,
  });

  @override
  final String headline;

  final String patientId;

  /// Name, age, sex, MRN — the one-line identity strip.
  final String identityLine;

  /// True for the "how are they progressing" reading, which leads with trends
  /// and observations rather than the standing record.
  final bool progression;

  /// The allergy banner text, when there is anything to warn about.
  final String? allergyLine;

  final List<String> problems;
  final List<String> medications;

  /// The most recent set of observations, label/value pairs already formatted.
  final List<({String label, String value})> vitals;

  /// The latest NEWS2 line, e.g. "NEWS2 6 — medium risk (2 h ago)".
  final String? news2Line;

  /// Observations moving the wrong way, one sentence each.
  final List<String> trends;

  /// The last few encounters, newest first.
  final List<({String when, String summary})> visits;

  /// Upcoming appointments, one line each.
  final List<String> upcoming;

  @override
  final MetricExplanation? explanation;
}
