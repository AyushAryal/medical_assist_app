import '../schema/field_registry.dart';

/// What to do with the values in a group.
enum Aggregate { count, sum, average, median, min, max, distinct }

extension AggregateX on Aggregate {
  String get label => switch (this) {
        Aggregate.count => 'Count',
        Aggregate.sum => 'Total',
        Aggregate.average => 'Average',
        Aggregate.median => 'Median',
        Aggregate.min => 'Lowest',
        Aggregate.max => 'Highest',
        Aggregate.distinct => 'Distinct',
      };

  /// How it reads in a sentence: "the average systolic BP".
  String get article => switch (this) {
        Aggregate.count => 'number of',
        Aggregate.sum => 'total',
        Aggregate.average => 'average',
        Aggregate.median => 'median',
        Aggregate.min => 'lowest',
        Aggregate.max => 'highest',
        Aggregate.distinct => 'distinct',
      };

  /// Whether it needs a numeric column. Counting does not.
  bool get needsMeasure => this != Aggregate.count;

  /// The words that ask for it.
  List<String> get triggers => switch (this) {
        Aggregate.count => const <String>['count', 'how many', 'number of',
            'total number', 'tally'],
        Aggregate.sum => const <String>['sum', 'total', 'combined',
            'added up'],
        Aggregate.average => const <String>['average', 'mean', 'avg',
            'typical', 'on average'],
        Aggregate.median => const <String>['median', 'middle', 'midpoint'],
        Aggregate.min => const <String>['minimum', 'lowest', 'min',
            'smallest', 'least'],
        Aggregate.max => const <String>['maximum', 'highest', 'max',
            'largest', 'peak', 'greatest'],
        Aggregate.distinct => const <String>['distinct', 'unique',
            'different', 'how many different'],
      };
}

/// How finely a timeline is cut.
enum TimeBucket { day, week, month, quarter, year }

extension TimeBucketX on TimeBucket {
  String get label => switch (this) {
        TimeBucket.day => 'day',
        TimeBucket.week => 'week',
        TimeBucket.month => 'month',
        TimeBucket.quarter => 'quarter',
        TimeBucket.year => 'year',
      };

  Duration get span => switch (this) {
        TimeBucket.day => const Duration(days: 1),
        TimeBucket.week => const Duration(days: 7),
        TimeBucket.month => const Duration(days: 30),
        TimeBucket.quarter => const Duration(days: 91),
        TimeBucket.year => const Duration(days: 365),
      };

  /// Snaps an instant to the start of its bucket.
  DateTime startOf(DateTime at) => switch (this) {
        TimeBucket.day => DateTime(at.year, at.month, at.day),
        // Monday. A clinic week that starts on Sunday puts the two busiest
        // days in different bars.
        TimeBucket.week => DateTime(at.year, at.month, at.day)
            .subtract(Duration(days: at.weekday - 1)),
        TimeBucket.month => DateTime(at.year, at.month),
        TimeBucket.quarter => DateTime(at.year, ((at.month - 1) ~/ 3) * 3 + 1),
        TimeBucket.year => DateTime(at.year),
      };

  static TimeBucket? fromWord(String word) => switch (word) {
        'day' || 'daily' || 'days' => TimeBucket.day,
        'week' || 'weekly' || 'weeks' => TimeBucket.week,
        'month' || 'monthly' || 'months' => TimeBucket.month,
        'quarter' || 'quarterly' || 'quarters' => TimeBucket.quarter,
        'year' || 'yearly' || 'annual' || 'years' => TimeBucket.year,
        _ => null,
      };
}

/// How the result should be drawn.
///
/// Chosen from the *shape of the answer* rather than asked for, because the
/// person asking a question usually knows what they want to know and not which
/// chart shows it. A pie of thirty diagnoses and a line through five unordered
/// categories are both technically charts and neither communicates anything.
enum ChartStyle { bar, column, line, area, pie, donut, scatter, histogram }

extension ChartStyleX on ChartStyle {
  String get label => switch (this) {
        ChartStyle.bar => 'Bar chart',
        ChartStyle.column => 'Column chart',
        ChartStyle.line => 'Line chart',
        ChartStyle.area => 'Area chart',
        ChartStyle.pie => 'Pie chart',
        ChartStyle.donut => 'Donut chart',
        ChartStyle.scatter => 'Scatter plot',
        ChartStyle.histogram => 'Histogram',
      };

  /// True where the slices must add up to a meaningful whole.
  bool get isShare => this == ChartStyle.pie || this == ChartStyle.donut;
}

/// One plotted value.
///
/// [n] travels with it because a bar built from four observations and a bar
/// built from four hundred look identical, and only one of them means
/// anything. Every renderer here can show it, and the explanation always does.
class ChartPoint {
  const ChartPoint({
    required this.label,
    required this.value,
    this.x,
    this.n = 0,
  });

  final String label;
  final double value;

  /// Horizontal position, for a scatter plot. Null everywhere else, where the
  /// position is the label's place in the list.
  final double? x;

  /// How many rows this point was computed from.
  final int n;
}

/// One analysis, fully specified.
///
/// Everything the engine needs and nothing it could misuse: the table and the
/// fields are registry objects, so by the time a spec exists the only strings
/// left are labels. There is no path from here to an identifier that a person
/// typed.
class AnalysisSpec {
  const AnalysisSpec({
    required this.table,
    required this.aggregate,
    this.measure,
    this.dimension,
    this.dimensionTable,
    this.against,
    this.againstTable,
    this.bucket = TimeBucket.week,
    this.style,
    this.preferTable = false,
    this.periodFrom,
    this.periodTo,
    this.maxGroups = 12,
    this.patientFields = const <DataField>[],
  });

  final DataTable table;
  final Aggregate aggregate;

  /// The numeric column being aggregated. Null when counting rows.
  final DataField? measure;

  /// What to group by. Null means one number for everything.
  final DataField? dimension;

  /// The table [dimension] lives on, when it is a patient attribute joined
  /// onto a clinical table — "observations by city".
  final DataTable? dimensionTable;

  /// A second numeric field, for a scatter plot: `against` on x, `measure` on
  /// y. Null for every other analysis.
  final DataField? against;
  final DataTable? againstTable;

  final TimeBucket bucket;

  /// Overrides the automatic choice, when someone asked for a shape by name.
  final ChartStyle? style;

  /// True where the wording asked for a table outright. The analysis is
  /// computed identically; only the first rendering changes.
  final bool preferTable;

  final DateTime? periodFrom;
  final DateTime? periodTo;

  /// Patient attributes to read alongside the subject's own columns — what a
  /// ranking needs to narrow by sex or age without a second query.
  final List<DataField> patientFields;

  /// Categories beyond this are folded into "Other".
  ///
  /// A chart with sixty bars is a table drawn badly. Keeping the top few and
  /// naming the remainder preserves the total, which a plain cut-off would
  /// quietly break.
  final int maxGroups;

  bool get isScatter => against != null && measure != null;
  bool get isTimeline => dimension?.kind == FieldKind.temporal;

  /// A question about the shape of one field rather than about a comparison.
  ///
  /// Keyed off the requested style rather than inferred from "no dimension":
  /// "average BMI" also has no dimension, and it wants one number, not a
  /// histogram of every reading behind it.
  bool get isDistribution =>
      style == ChartStyle.histogram && measure != null && dimension == null;

  AnalysisSpec copyWith({
    Aggregate? aggregate,
    DataField? dimension,
    DataTable? dimensionTable,
    TimeBucket? bucket,
    ChartStyle? style,
    bool clearDimension = false,
  }) =>
      AnalysisSpec(
        table: table,
        aggregate: aggregate ?? this.aggregate,
        measure: measure,
        dimension: clearDimension ? null : (dimension ?? this.dimension),
        dimensionTable:
            clearDimension ? null : (dimensionTable ?? this.dimensionTable),
        against: against,
        againstTable: againstTable,
        bucket: bucket ?? this.bucket,
        style: style ?? this.style,
        preferTable: preferTable,
        periodFrom: periodFrom,
        periodTo: periodTo,
        maxGroups: maxGroups,
        patientFields: patientFields,
      );

  /// The chart this asks for, unless one was named.
  ///
  /// The rules are ordinary chart-choosing practice, written down so they are
  /// applied consistently rather than per call site:
  ///
  /// * Two numeric fields is a scatter — the question is whether they move
  ///   together, and nothing else shows that.
  /// * A timeline is a line, or an area when it is a count filling in from
  ///   zero.
  /// * Shares of a whole read best as a donut, but only for a handful of
  ///   slices and only when the parts genuinely sum to the total — an average
  ///   per category does not, and drawing it as a pie states something false.
  /// * Everything else is bars, horizontal once the labels are words rather
  ///   than dates.
  ChartStyle styleFor(int groupCount) {
    if (style != null) return style!;
    if (isScatter) return ChartStyle.scatter;
    if (isTimeline) {
      return aggregate == Aggregate.count ? ChartStyle.area : ChartStyle.line;
    }
    final partsSumToWhole =
        aggregate == Aggregate.count || aggregate == Aggregate.sum;
    if (partsSumToWhole && groupCount >= 2 && groupCount <= 6) {
      return ChartStyle.donut;
    }
    return ChartStyle.bar;
  }

  /// How this reads back, so the person asking can see it was understood.
  String describe() {
    final what = measure == null
        ? '${aggregate.article} ${table.label}'
        : '${aggregate.article} ${measure!.label.toLowerCase()}';
    final by = switch (dimension) {
      null => '',
      final field when field.kind == FieldKind.temporal =>
        ' per ${bucket.label}',
      final field => ' by ${field.label.toLowerCase()}',
    };
    final versus =
        against == null ? '' : ' against ${against!.label.toLowerCase()}';
    return '$what$by$versus';
  }
}
