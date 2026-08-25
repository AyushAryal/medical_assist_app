import '../schema/field_registry.dart';
import 'analysis.dart';
import 'period_parser.dart';

/// Reads an analytical question into an [AnalysisSpec].
///
/// Coded logic, not a model, and the reason is the same one that governs the
/// rest of this pipeline: the vocabulary is closed. There are nine tables and
/// a hundred-odd fields, every one of them already written down with the words
/// people use for it, so the work is matching phrases to registry entries —
/// which is instant, offline, identical on every device, and can show its
/// working. A model's contribution here would be to guess at the same table,
/// slower and unverifiably.
///
/// The grammar is small and deliberately so. Almost everything anyone asks of
/// a register is one of:
///
/// ```
///   <aggregate> <measure>                    average waiting time
///   <aggregate> <measure> by <dimension>     average bmi by district
///   <subject>   by <dimension>               visits by clinician
///   <subject>   per <bucket>                 appointments per month
///   <measure>   against <measure>            weight against height
///   distribution of <measure>                spread of systolic bp
/// ```
///
/// Anything it cannot place, it declines. Returning null hands the question
/// back to the cohort matcher, which is a better answer than a confident chart
/// of the wrong column.
abstract final class AnalysisParser {
  /// Words that split a question into what is measured and what it is cut by.
  static final RegExp _splitter = RegExp(
    r'\s+(?:broken down by|grouped by|split by|by|per|across|for each|'
    r'against|versus|vs\.?|compared (?:to|with))\s+',
  );

  static final RegExp _scatterJoin =
      RegExp(r'\s+(?:against|versus|vs\.?|compared (?:to|with))\s+');

  static final RegExp _distribution = RegExp(
    r'\b(?:distribution|spread|histogram|range|variation)\s+(?:of|in|for)\s+',
  );

  static AnalysisSpec? parse(String question, {DateTime? asOf}) {
    var text = _normalise(question);
    if (text.isEmpty) return null;

    final now = asOf ?? DateTime.now();

    // A named table is a rendering preference, not a different analysis: the
    // spec is computed identically and the answer opens tabulated.
    final wantsTable =
        RegExp(r'\b(?:as|in) a table\b|\btabular\b').hasMatch(text);
    if (wantsTable) {
      text = _tidy(text.replaceAll(
        RegExp(r'\b(?:as|in) a table\b|\btabular\b'),
        ' ',
      ));
    }

    // Peeled off in order, longest phrase first, so "how many different" is
    // read as distinct rather than as count followed by a stray word.
    final style = _takeStyle(text);
    text = style.rest;
    final period = PeriodParser.take(style.rest, now);
    text = period.rest;
    final bucket = _takeBucket(text);
    text = bucket.rest;
    final aggregate = _takeAggregate(text);
    text = aggregate.rest;

    // Stripped before tidying: "spread of systolic bp" loses its "of" to the
    // tidier, and the phrase would no longer match itself afterwards.
    final wantsDistribution = _distribution.hasMatch(text);
    if (wantsDistribution) text = text.replaceFirst(_distribution, ' ');
    text = _tidy(text);

    final isScatter = _scatterJoin.hasMatch(question.toLowerCase());
    final parts = text.split(_splitter).map(_tidy).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return null;

    final left = parts.first;
    final right = parts.length > 1 ? parts.elementAt(1) : null;

    final leftField = FieldRegistry.resolveField(left);
    final leftTable = FieldRegistry.resolveTable(left);
    final rightField = right == null ? null : FieldRegistry.resolveField(right);
    final rightTable = right == null ? null : FieldRegistry.resolveTable(right);

    // Nothing recognised at all. Not this parser's question.
    if (leftField == null && leftTable == null) return null;

    // A bare table name is a cohort question — "appointments", "patients" —
    // and the cohort matcher answers those better, with records to open.
    if (leftField == null &&
        right == null &&
        !wantsDistribution &&
        bucket.value == null &&
        style.value == null &&
        aggregate.value == null) {
      return null;
    }

    final measure = leftField != null && leftField.field.kind == FieldKind.numeric
        ? leftField.field
        : null;

    // Explicitly named tables win. "visits by city" is a question about
    // visits, even though `city` lives on patients and would otherwise drag
    // the subject with it.
    final subject = _subjectFor(
      named: leftTable?.table ?? rightTable?.table,
      measureOwner: leftField?.table,
      dimensionOwner: rightField?.table,
      measure: measure,
    );
    if (subject == null) return null;

    if (isScatter && rightField != null &&
        rightField.field.kind == FieldKind.numeric &&
        measure != null) {
      return AnalysisSpec(
        table: subject,
        aggregate: Aggregate.average,
        measure: measure,
        against: rightField.field,
        againstTable: rightField.table,
        style: ChartStyle.scatter,
        preferTable: wantsTable,
        periodFrom: period.from,
        periodTo: period.to,
      );
    }

    // "per week" with nothing to group by means the subject's own timeline.
    final DataField? dimension;
    final DataTable? dimensionTable;
    if (rightField != null) {
      dimension = rightField.field;
      dimensionTable = rightField.table;
    } else if (bucket.value != null || style.value == ChartStyle.line) {
      dimension = subject.defaultTime;
      dimensionTable = subject;
    } else {
      dimension = null;
      dimensionTable = null;
    }

    // A plain count of a table with nothing to cut it by is a cohort
    // question, not a chart. The cohort matcher answers those with the records
    // behind the number, and a number you cannot open is a dead end.
    if (dimension == null && measure == null && !wantsDistribution) {
      return null;
    }

    // A dimension the reader cannot group by. Prose has as many values as it
    // has rows, and so does an identifier — a chart grouped by phone number is
    // one bar per patient, which is a table drawn badly.
    if (dimension != null &&
        (dimension.kind == FieldKind.text ||
            dimension.kind == FieldKind.identifier)) {
      return null;
    }

    final chosen = aggregate.value ??
        (measure == null ? Aggregate.count : Aggregate.average);

    // Asked to average something that is not a number.
    if (chosen.needsMeasure && measure == null && !wantsDistribution) {
      if (leftField != null && leftField.field.kind != FieldKind.numeric) {
        return null;
      }
    }

    return AnalysisSpec(
      table: subject,
      aggregate: wantsDistribution ? Aggregate.count : chosen,
      measure: measure,
      dimension: wantsDistribution ? null : dimension,
      dimensionTable: wantsDistribution ? null : dimensionTable,
      bucket: bucket.value ?? TimeBucket.week,
      style: style.value ?? (wantsDistribution ? ChartStyle.histogram : null),
      preferTable: wantsTable,
      periodFrom: period.from,
      periodTo: period.to,
    );
  }

  static DataTable? _subjectFor({
    required DataTable? named,
    required DataTable? measureOwner,
    required DataTable? dimensionOwner,
    required DataField? measure,
  }) {
    if (named != null) return named;
    if (measure != null && measureOwner != null) return measureOwner;
    if (measureOwner != null) return measureOwner;
    if (dimensionOwner != null) return dimensionOwner;
    return null;
  }

  /// The modifiers present in a *fragment* — "per month instead", "as a pie",
  /// "median" — for refining a standing analysis without re-deriving it.
  ///
  /// A fragment is not a question: it has no subject of its own, which is
  /// exactly why [parse] returns null for it and why the conversation layer
  /// needs this weaker reading instead.
  static ({
    Aggregate? aggregate,
    TimeBucket? bucket,
    ChartStyle? style,
    DateTime? periodFrom,
    DateTime? periodTo,
    FieldMatch? dimension,
    bool hasAny,
  }) fragments(String question, {DateTime? asOf}) {
    var text = _normalise(question);
    final now = asOf ?? DateTime.now();

    final style = _takeStyle(text);
    text = style.rest;
    final period = PeriodParser.take(text, now);
    text = period.rest;
    final bucket = _takeBucket(text);
    text = bucket.rest;
    final aggregate = _takeAggregate(text);
    text = _tidy(aggregate.rest);

    FieldMatch? dimension;
    if (text.isNotEmpty) {
      final candidate = FieldRegistry.resolveField(text);
      if (candidate != null &&
          candidate.field.kind != FieldKind.text &&
          candidate.field.kind != FieldKind.identifier) {
        dimension = candidate;
      }
    }

    return (
      aggregate: aggregate.value,
      bucket: bucket.value,
      style: style.value,
      periodFrom: period.from,
      periodTo: period.to,
      dimension: dimension,
      hasAny: aggregate.value != null ||
          bucket.value != null ||
          style.value != null ||
          period.from != null ||
          dimension != null,
    );
  }

  static ({ChartStyle? value, String rest}) _takeStyle(String text) {
    const phrases = <String, ChartStyle>{
      'as a pie chart': ChartStyle.pie,
      'as a pie': ChartStyle.pie,
      'pie chart': ChartStyle.pie,
      'donut chart': ChartStyle.donut,
      'doughnut chart': ChartStyle.donut,
      'as a line chart': ChartStyle.line,
      'line chart': ChartStyle.line,
      'line graph': ChartStyle.line,
      'as a line': ChartStyle.line,
      'area chart': ChartStyle.area,
      'scatter plot': ChartStyle.scatter,
      'scatterplot': ChartStyle.scatter,
      'scatter chart': ChartStyle.scatter,
      'bar chart': ChartStyle.bar,
      'bar graph': ChartStyle.bar,
      'column chart': ChartStyle.column,
      'as bars': ChartStyle.bar,
      'histogram': ChartStyle.histogram,
    };
    for (final entry in phrases.entries) {
      if (text.contains(entry.key)) {
        return (value: entry.value, rest: _tidy(text.replaceAll(entry.key, ' ')));
      }
    }
    return (value: null, rest: text);
  }

  static ({Aggregate? value, String rest}) _takeAggregate(String text) {
    // Longest first: "how many different" must beat "how many".
    final ordered = <({Aggregate aggregate, String phrase})>[
      for (final aggregate in Aggregate.values)
        for (final phrase in aggregate.triggers)
          (aggregate: aggregate, phrase: phrase),
    ]..sort((a, b) => b.phrase.length.compareTo(a.phrase.length));

    for (final entry in ordered) {
      final pattern = RegExp('\\b${RegExp.escape(entry.phrase)}\\b');
      if (pattern.hasMatch(text)) {
        return (
          value: entry.aggregate,
          rest: _tidy(text.replaceFirst(pattern, ' ')),
        );
      }
    }
    return (value: null, rest: text);
  }

  static ({TimeBucket? value, String rest}) _takeBucket(String text) {
    final match = RegExp(
      r'\b(?:per|each|every|by|over the last|in the last)?\s*'
      r'(day|daily|days|week|weekly|weeks|month|monthly|months|'
      r'quarter|quarterly|quarters|year|yearly|annual|years)\b',
    ).firstMatch(text);

    // "over time" and "trend" ask for a timeline without naming a grain.
    if (match == null) {
      final loose = RegExp(r'\b(?:over time|trend|trending|timeline)\b');
      if (loose.hasMatch(text)) {
        return (
          value: TimeBucket.week,
          rest: _tidy(text.replaceFirst(loose, ' ')),
        );
      }
      return (value: null, rest: text);
    }

    final bucket = TimeBucketX.fromWord(match.group(1)!);
    if (bucket == null) return (value: null, rest: text);

    // "last 6 months" is a period, not a grain — handled before this runs, so
    // anything still carrying a number is left alone.
    final before = text.substring(0, match.start).trimRight();
    if (RegExp(r'\d+$').hasMatch(before)) return (value: null, rest: text);

    return (
      value: bucket,
      rest: _tidy(text.replaceRange(match.start, match.end, ' ')),
    );
  }

  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[?!.,;:]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Strips the connective tissue a phrase is left with once its keywords are
  /// removed, so "the of visits" resolves as "visits".
  static String _tidy(String value) => value
      .replaceAll(
        RegExp(r'\b(?:the|a|an|of|in|for|our|my|all|show|me|give|chart|graph|'
            r'plot|please|what|whats|is|are|was|were|do|does|there|their|'
            r'and|with|has|have|had|been|be|it|this|that|about|us)\b'),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
