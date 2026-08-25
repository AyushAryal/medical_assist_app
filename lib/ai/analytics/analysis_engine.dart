import 'dart:math' as math;

import '../../core/utils/formatters.dart';
import '../../data/dao/analysis_dao.dart';
import '../schema/field_registry.dart';
import 'analysis.dart';
import 'statistics.dart';

/// A finished analysis: the points to draw, and what can honestly be said.
class AnalysisResult {
  const AnalysisResult({
    required this.spec,
    required this.points,
    required this.style,
    required this.rowsRead,
    required this.missing,
    this.stats,
    this.correlation,
    this.trend,
    this.truncated = false,
    this.caveats = const <String>[],
  });

  final AnalysisSpec spec;
  final List<ChartPoint> points;
  final ChartStyle style;

  /// Rows the analysis actually saw.
  final int rowsRead;

  /// Rows dropped for having no value in the measured column.
  final int missing;

  /// Over the measured values, across every group.
  final Stats? stats;

  /// Scatter plots only.
  final Correlation? correlation;

  /// Timelines only.
  final Trend? trend;

  final bool truncated;

  /// Things a reader has to know before believing the chart.
  final List<String> caveats;

  bool get isEmpty => points.isEmpty || points.every((p) => p.value == 0);

  double get total => points.fold<double>(0, (a, p) => a + p.value);
}

/// Turns rows into a chart.
///
/// Kept separate from the DAO so it can be tested against a hand-written list
/// of maps — every rule below (bucketing, folding a long tail into "Other",
/// dropping a group with too few rows to mean anything) is a decision about
/// what is honest to draw, and those are exactly the decisions that should not
/// need a database to check.
abstract final class AnalysisEngine {
  /// Bins for a histogram. Sturges' rule, capped: enough to show a shape,
  /// few enough that each bar still has rows in it.
  static int _binCount(int n) =>
      n < 8 ? 4 : math.min(12, (1 + math.log(n) / math.ln2).ceil());

  /// Scatter points beyond this are drawn as a sample. Past a few thousand the
  /// plot is a solid block and more points add nothing but time.
  static const int _maxScatterPoints = 2000;

  static AnalysisResult run(AnalysisSpec spec, AnalysisRows data) {
    final caveats = <String>[
      if (data.truncated)
        'Only the first ${AnalysisDao.maxRows} rows were read, so this is a '
            'sample rather than the whole register.',
    ];

    if (spec.isScatter) return _scatter(spec, data, caveats);
    if (spec.isDistribution) return _histogram(spec, data, caveats);
    if (spec.dimension == null) return _single(spec, data, caveats);
    return switch (spec.dimension!.kind) {
      FieldKind.temporal => _timeline(spec, data, caveats),
      FieldKind.numeric => _binnedBy(spec, data, caveats),
      _ => _byCategory(spec, data, caveats),
    };
  }

  /// The prefix a field's columns were selected under.
  static String _prefixFor(AnalysisSpec spec, DataTable? owner) =>
      owner != null &&
              owner.name == FieldRegistry.patients.name &&
              spec.table.name != FieldRegistry.patients.name
          ? AnalysisDao.patientPrefix
          : AnalysisDao.subjectPrefix;

  /// Applies the aggregate to one group's values.
  static double _apply(Aggregate aggregate, List<double> values, int rows) {
    if (aggregate == Aggregate.count) return rows.toDouble();
    if (values.isEmpty) return 0;
    final stats = Stats.of(values)!;
    return switch (aggregate) {
      Aggregate.sum => stats.sum,
      Aggregate.average => stats.mean,
      Aggregate.median => stats.median,
      Aggregate.min => stats.min,
      Aggregate.max => stats.max,
      Aggregate.distinct => values.toSet().length.toDouble(),
      Aggregate.count => rows.toDouble(),
    };
  }

  static AnalysisResult _single(
    AnalysisSpec spec,
    AnalysisRows data,
    List<String> caveats,
  ) {
    final values = _measureValues(spec, data);
    final stats = Stats.of(values.present, missing: values.missing);
    final value = _apply(spec.aggregate, values.present, data.rows.length);

    return AnalysisResult(
      spec: spec,
      points: <ChartPoint>[
        ChartPoint(
          label: spec.measure?.label ?? spec.table.label,
          value: value,
          n: spec.aggregate == Aggregate.count
              ? data.rows.length
              : values.present.length,
        ),
      ],
      style: ChartStyle.bar,
      rowsRead: data.rows.length,
      missing: values.missing,
      stats: stats,
      truncated: data.truncated,
      caveats: caveats,
    );
  }

  static AnalysisResult _byCategory(
    AnalysisSpec spec,
    AnalysisRows data,
    List<String> caveats,
  ) {
    final dimension = spec.dimension!;
    final prefix = _prefixFor(spec, spec.dimensionTable);
    final measurePrefix = _prefixFor(spec, spec.table);

    final buckets = <String, List<double>>{};
    final counts = <String, int>{};
    var unlabelled = 0;
    var missing = 0;

    for (final row in data.rows) {
      final label = dimension.labelIn(row, prefix: prefix);
      if (label == null) {
        unlabelled++;
        continue;
      }
      counts[label] = (counts[label] ?? 0) + 1;
      if (spec.measure != null) {
        final value = spec.measure!.numberIn(row, prefix: measurePrefix);
        if (value == null) {
          missing++;
        } else {
          (buckets[label] ??= <double>[]).add(value);
        }
      }
    }

    var entries = <ChartPoint>[
      for (final label in counts.keys)
        ChartPoint(
          label: label,
          value: _apply(
            spec.aggregate,
            buckets[label] ?? const <double>[],
            counts[label]!,
          ),
          n: counts[label]!,
        ),
    ]..sort((a, b) => b.value.compareTo(a.value));

    // A long tail is folded rather than cut. Dropping the smallest categories
    // silently changes the total, and a chart whose parts no longer add up to
    // the number printed above it is the fastest way to lose a reader's trust.
    if (entries.length > spec.maxGroups) {
      final kept = entries.take(spec.maxGroups - 1).toList();
      final rest = entries.skip(spec.maxGroups - 1).toList();
      final restRows = rest.fold<int>(0, (a, p) => a + p.n);
      kept.add(ChartPoint(
        label: 'Other (${rest.length})',
        // Only a sum can be folded. An average of averages is not an average,
        // so for anything else the tail is counted, not combined.
        value: spec.aggregate == Aggregate.count || spec.aggregate == Aggregate.sum
            ? rest.fold<double>(0, (a, p) => a + p.value)
            : restRows.toDouble(),
        n: restRows,
      ));
      entries = kept;
      caveats.add(
        'The ${rest.length} smallest groups are combined into "Other".',
      );
    }

    if (unlabelled > 0) {
      caveats.add(
        '$unlabelled ${unlabelled == 1 ? 'row has' : 'rows have'} no '
        '${dimension.label.toLowerCase()} recorded and ${unlabelled == 1 ? 'is' : 'are'} '
        'left out of every group.',
      );
    }

    final all = buckets.values.expand((v) => v).toList();
    return AnalysisResult(
      spec: spec,
      points: entries,
      style: spec.styleFor(entries.length),
      rowsRead: data.rows.length,
      missing: missing,
      stats: Stats.of(all, missing: missing),
      truncated: data.truncated,
      caveats: caveats,
    );
  }

  static AnalysisResult _timeline(
    AnalysisSpec spec,
    AnalysisRows data,
    List<String> caveats,
  ) {
    final dimension = spec.dimension!;
    final prefix = _prefixFor(spec, spec.dimensionTable);
    final measurePrefix = _prefixFor(spec, spec.table);
    final bucket = spec.bucket;

    final buckets = <DateTime, List<double>>{};
    final counts = <DateTime, int>{};
    var missing = 0;
    var undated = 0;

    for (final row in data.rows) {
      final at = _instant(dimension.read(row, prefix: prefix));
      if (at == null) {
        undated++;
        continue;
      }
      final key = bucket.startOf(at);
      counts[key] = (counts[key] ?? 0) + 1;
      if (spec.measure != null) {
        final value = spec.measure!.numberIn(row, prefix: measurePrefix);
        if (value == null) {
          missing++;
        } else {
          (buckets[key] ??= <double>[]).add(value);
        }
      }
    }

    if (counts.isEmpty) {
      return AnalysisResult(
        spec: spec,
        points: const <ChartPoint>[],
        style: spec.styleFor(0),
        rowsRead: data.rows.length,
        missing: missing,
        truncated: data.truncated,
        caveats: caveats,
      );
    }

    // Empty buckets are filled in. A month with no visits is a fact about the
    // clinic; leaving it out draws a line straight over it and hides exactly
    // the gap someone is looking for.
    final ordered = counts.keys.toList()..sort();
    final points = <ChartPoint>[];
    for (var at = ordered.first;
        !at.isAfter(ordered.last);
        at = bucket.startOf(at.add(bucket.span + const Duration(hours: 12)))) {
      final rows = counts[at] ?? 0;
      final values = buckets[at] ?? const <double>[];
      // An average over an empty bucket is not zero, it is unknown; drawing it
      // as zero invents a crash that never happened.
      final skip = rows == 0 && spec.aggregate != Aggregate.count;
      points.add(ChartPoint(
        label: _bucketLabel(at, bucket),
        value: skip ? double.nan : _apply(spec.aggregate, values, rows),
        n: rows,
      ));
      if (points.length > 200) break;
    }

    final series =
        points.map((p) => p.value).where((v) => !v.isNaN).toList();
    final all = buckets.values.expand((v) => v).toList();

    if (undated > 0) {
      caveats.add('$undated row${undated == 1 ? '' : 's'} with no date are '
          'not on the timeline.');
    }
    caveats.add('The last ${bucket.label} is still filling, so it will almost '
        'always look short.');

    return AnalysisResult(
      spec: spec,
      points: points,
      style: spec.styleFor(points.length),
      rowsRead: data.rows.length,
      missing: missing,
      stats: Stats.of(all.isEmpty ? series : all, missing: missing),
      // Computed without the final bucket for the same reason it is flagged:
      // a part-finished period drags every trend downwards.
      trend: Trend.of(
        series.length > 3 ? series.sublist(0, series.length - 1) : series,
      ),
      truncated: data.truncated,
      caveats: caveats,
    );
  }

  static AnalysisResult _binnedBy(
    AnalysisSpec spec,
    AnalysisRows data,
    List<String> caveats,
  ) {
    final dimension = spec.dimension!;
    final prefix = _prefixFor(spec, spec.dimensionTable);
    final measurePrefix = _prefixFor(spec, spec.table);

    final raw = <({double at, double? value})>[];
    var missing = 0;
    for (final row in data.rows) {
      final at = dimension.numberIn(row, prefix: prefix);
      if (at == null) continue;
      final value = spec.measure?.numberIn(row, prefix: measurePrefix);
      if (spec.measure != null && value == null) missing++;
      raw.add((at: at, value: value));
    }
    if (raw.isEmpty) {
      return AnalysisResult(
        spec: spec,
        points: const <ChartPoint>[],
        style: ChartStyle.bar,
        rowsRead: data.rows.length,
        missing: missing,
        truncated: data.truncated,
        caveats: caveats,
      );
    }

    final positions = raw.map((r) => r.at).toList()..sort();
    final low = positions.first;
    final high = positions.last;
    final bins = _binCount(positions.length);
    final width = (high - low) / bins;

    final grouped = List<List<double>>.generate(bins, (_) => <double>[]);
    final counts = List<int>.filled(bins, 0);
    for (final entry in raw) {
      final index = width == 0
          ? 0
          : math.min(bins - 1, ((entry.at - low) / width).floor());
      counts[index]++;
      if (entry.value != null) grouped[index].add(entry.value!);
    }

    final unit = dimension.unit == null ? '' : ' ${dimension.unit}';
    return AnalysisResult(
      spec: spec,
      points: <ChartPoint>[
        for (var i = 0; i < bins; i++)
          ChartPoint(
            label: width == 0
                ? Fmt.number(low, decimals: 0)
                : '${Fmt.number(low + i * width, decimals: 0)}–'
                    '${Fmt.number(low + (i + 1) * width, decimals: 0)}$unit',
            value: _apply(spec.aggregate, grouped[i], counts[i]),
            n: counts[i],
          ),
      ],
      style: ChartStyle.histogram,
      rowsRead: data.rows.length,
      missing: missing,
      stats: Stats.of(
        grouped.expand((g) => g).toList().isEmpty
            ? positions
            : grouped.expand((g) => g).toList(),
        missing: missing,
      ),
      truncated: data.truncated,
      caveats: caveats,
    );
  }

  static AnalysisResult _histogram(
    AnalysisSpec spec,
    AnalysisRows data,
    List<String> caveats,
  ) {
    final values = _measureValues(spec, data);
    if (values.present.isEmpty) {
      return AnalysisResult(
        spec: spec,
        points: const <ChartPoint>[],
        style: ChartStyle.histogram,
        rowsRead: data.rows.length,
        missing: values.missing,
        truncated: data.truncated,
        caveats: caveats,
      );
    }

    final sorted = List<double>.of(values.present)..sort();
    final low = sorted.first;
    final high = sorted.last;
    final bins = _binCount(sorted.length);
    final width = (high - low) / bins;
    final counts = List<int>.filled(bins, 0);
    for (final value in sorted) {
      counts[width == 0
          ? 0
          : math.min(bins - 1, ((value - low) / width).floor())]++;
    }

    final unit = spec.measure?.unit == null ? '' : ' ${spec.measure!.unit}';
    final outliers = Stats.outliers(sorted);
    if (outliers.isNotEmpty) {
      caveats.add('${outliers.length} value${outliers.length == 1 ? '' : 's'} '
          'sit well outside the rest and are worth checking for a '
          'transcription slip.');
    }

    return AnalysisResult(
      spec: spec,
      points: <ChartPoint>[
        for (var i = 0; i < bins; i++)
          ChartPoint(
            label: width == 0
                ? '${Fmt.number(low)}$unit'
                : '${Fmt.number(low + i * width, decimals: 0)}–'
                    '${Fmt.number(low + (i + 1) * width, decimals: 0)}$unit',
            value: counts[i].toDouble(),
            n: counts[i],
          ),
      ],
      style: ChartStyle.histogram,
      rowsRead: data.rows.length,
      missing: values.missing,
      stats: Stats.of(sorted, missing: values.missing),
      truncated: data.truncated,
      caveats: caveats,
    );
  }

  static AnalysisResult _scatter(
    AnalysisSpec spec,
    AnalysisRows data,
    List<String> caveats,
  ) {
    final xPrefix = _prefixFor(spec, spec.againstTable);
    final yPrefix = _prefixFor(spec, spec.table);
    final pairs = <({double x, double y})>[];
    var missing = 0;

    for (final row in data.rows) {
      final x = spec.against!.numberIn(row, prefix: xPrefix);
      final y = spec.measure!.numberIn(row, prefix: yPrefix);
      if (x == null || y == null) {
        missing++;
        continue;
      }
      pairs.add((x: x, y: y));
    }

    final correlation = Correlation.of(pairs);
    if (correlation != null && correlation.isMeaningful) {
      caveats.add('Two things moving together in a register is not one causing '
          'the other. Anything that affects both — age, season, which clinic — '
          'produces the same picture.');
    }

    final drawn = pairs.length > _maxScatterPoints
        ? (pairs..shuffle(math.Random(7))).take(_maxScatterPoints).toList()
        : pairs;
    if (pairs.length > _maxScatterPoints) {
      caveats.add('Showing $_maxScatterPoints of ${pairs.length} points.');
    }

    return AnalysisResult(
      spec: spec,
      points: <ChartPoint>[
        for (final pair in drawn)
          ChartPoint(label: '', value: pair.y, x: pair.x, n: 1),
      ],
      style: ChartStyle.scatter,
      rowsRead: data.rows.length,
      missing: missing,
      stats: Stats.of(pairs.map((p) => p.y).toList(), missing: missing),
      correlation: correlation,
      truncated: data.truncated,
      caveats: caveats,
    );
  }

  static ({List<double> present, int missing}) _measureValues(
    AnalysisSpec spec,
    AnalysisRows data,
  ) {
    if (spec.measure == null) {
      return (present: const <double>[], missing: 0);
    }
    final prefix = _prefixFor(spec, spec.table);
    final present = <double>[];
    var missing = 0;
    for (final row in data.rows) {
      final value = spec.measure!.numberIn(row, prefix: prefix);
      if (value == null) {
        missing++;
      } else {
        present.add(value);
      }
    }
    return (present: present, missing: missing);
  }

  static DateTime? _instant(Object? raw) {
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static String _bucketLabel(DateTime at, TimeBucket bucket) =>
      switch (bucket) {
        TimeBucket.day || TimeBucket.week => Fmt.dateShort(at),
        TimeBucket.month => Fmt.monthAndYear(at),
        TimeBucket.quarter => 'Q${(at.month - 1) ~/ 3 + 1} ${at.year}',
        TimeBucket.year => '${at.year}',
      };
}
