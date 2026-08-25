import '../../clinical/explanations.dart';
import '../../core/utils/formatters.dart';
import '../../data/dao/analysis_dao.dart';
import '../analytics/analysis.dart';
import '../analytics/analysis_engine.dart';
import '../intent.dart';
import '../presentation.dart';
import '../provenance.dart';
import '../schema/field_registry.dart';

/// Runs an [AnalysisIntent] and turns it into something worth looking at.
///
/// The interesting work here is not the arithmetic — that is
/// [AnalysisEngine] — but deciding what the chart is allowed to claim. A chart
/// drawn from eleven rows with sixty per cent of the column empty looks
/// identical to one drawn from four thousand complete ones, and the difference
/// is the whole question of whether to act on it. So every answer carries the
/// count it was built from, what was missing, and the caveats that apply.
class AnalysisHandler {
  const AnalysisHandler(this._dao);

  final AnalysisDao _dao;

  /// Below this, a breakdown is anecdote with axes.
  static const int _thinEvidence = 12;

  Future<Presentation> run(AnalysisIntent intent, Provenance provenance) async {
    final spec = intent.spec;
    final data = await _dao.read(spec);

    provenance.add(
      'execute',
      'Read ${data.rows.length} rows from ${spec.table.label}',
      detail: 'Only the columns this analysis names were read: '
          '${_columnsUsed(spec).join(', ')}.',
    );

    final result = AnalysisEngine.run(spec, data);

    provenance.add(
      'analyse',
      '${spec.aggregate.label} over '
          '${result.points.length} ${result.points.length == 1 ? 'group' : 'groups'}',
      detail: result.missing == 0
          ? null
          : '${result.missing} rows had no value recorded and are excluded.',
      confidence: _confidenceFrom(result),
    );

    if (result.isEmpty) {
      return MessagePresentation(
        headline: 'Nothing recorded for ${spec.describe()}.',
        suggestions: <String>[
          '${spec.table.label} per month',
          for (final field in spec.table.ofKind(FieldKind.categorical).take(2))
            '${spec.table.label} by ${field.label.toLowerCase()}',
        ],
      );
    }

    return ChartPresentation(
      style: result.style,
      points: result.points,
      headline: _headline(result),
      caption: _caption(result),
      valueLabel: _valueLabel(spec),
      axisLabel: spec.dimension?.label,
      unit: spec.aggregate == Aggregate.count ? null : spec.measure?.unit,
      stats: result.stats,
      correlation: result.correlation,
      trend: result.trend,
      footnotes: result.caveats,
      preferTable: spec.preferTable,
      explanation: _explain(result),
    );
  }

  static List<String> _columnsUsed(AnalysisSpec spec) => <String>{
        for (final field in <DataField?>[
          spec.measure,
          spec.dimension,
          spec.against,
        ])
          if (field != null) ...field.columns,
      }.toList();

  /// Confidence in the *answer*, not in having understood the question.
  ///
  /// Those are different things and conflating them is how a chart of nine
  /// records ends up presented as firmly as one of nine thousand. The question
  /// may have been read perfectly and the data still be too thin to say
  /// anything.
  static double _confidenceFrom(AnalysisResult result) {
    final stats = result.stats;
    if (stats == null) return result.rowsRead >= _thinEvidence ? 0.8 : 0.4;
    final completeness = stats.completeness;
    final volume = (stats.count / (_thinEvidence * 4)).clamp(0.2, 1.0);
    return (completeness * 0.5 + volume * 0.5).clamp(0.1, 0.95);
  }

  static String _headline(AnalysisResult result) {
    final spec = result.spec;

    if (result.correlation case final correlation?
        when correlation.isMeaningful) {
      return '${spec.measure!.label} ${correlation.direction} '
          '${spec.against!.label.toLowerCase()} — ${correlation.strength} '
          'across ${correlation.n} records.';
    }

    if (spec.dimension == null && result.points.length == 1) {
      final point = result.points.first;
      return '${spec.aggregate.label} ${spec.measure?.label.toLowerCase() ?? spec.table.label}: '
          '${_number(point.value)}${_unitSuffix(spec)} '
          'from ${point.n} ${point.n == 1 ? 'record' : 'records'}.';
    }

    if (result.trend case final trend? when spec.isTimeline) {
      final per = spec.bucket.label;
      // Where the field has a better direction, say which one this is. For a
      // waiting time or an early-warning score, "rising" and "worse" are the
      // same news and the reader should not have to work that out.
      final reading =
          trend.readingFor(higherIsBetter: spec.measure?.higherIsBetter);
      final direction = trend.isFlat
          ? 'holding steady'
          : '${trend.direction} by about '
              '${_number(trend.slopePerStep.abs())} a $per'
              '${reading == null ? '' : ' — $reading'}';
      return '${_titleCase(spec.describe())} — $direction.';
    }

    final top = result.points.reduce(
      (a, b) => b.value.isNaN || a.value >= b.value ? a : b,
    );
    return '${_titleCase(spec.describe())} — highest is ${top.label} at '
        '${_number(top.value)}${_unitSuffix(spec)}.';
  }

  static String _caption(AnalysisResult result) {
    final spec = result.spec;
    final parts = <String>[
      result.style.label,
      '${result.rowsRead} ${result.rowsRead == 1 ? 'row' : 'rows'} read',
      if (result.missing > 0) '${result.missing} without a value',
      if (spec.periodFrom != null)
        'from ${Fmt.dateShort(spec.periodFrom)}',
    ];
    return parts.join(' · ');
  }

  static String? _valueLabel(AnalysisSpec spec) {
    if (spec.measure == null) {
      return 'Number of ${spec.table.label}';
    }
    return '${spec.aggregate.label} ${spec.measure!.label.toLowerCase()}';
  }

  static MetricExplanation _explain(AnalysisResult result) {
    final spec = result.spec;
    final stats = result.stats;

    return MetricExplanation(
      title: _titleCase(spec.describe()),
      summary: 'Computed on this device from '
          '${result.rowsRead} ${spec.table.label} '
          '${result.rowsRead == 1 ? 'record' : 'records'}.',
      method: <String>[
        'The ${spec.table.label} table was read for only the columns this '
            'question needs — ${_columnsUsed(spec).join(', ')} — and every '
            'value below was computed here, not fetched from anywhere.',
        if (spec.measure != null)
          'Rows with no ${spec.measure!.label.toLowerCase()} recorded are '
              'left out rather than counted as zero. A missing reading is not '
              'a reading of nothing.',
        if (spec.dimension != null &&
            spec.dimension!.kind == FieldKind.temporal)
          'Buckets with no records are drawn as gaps rather than joined '
              'across, so a quiet ${spec.bucket.label} looks quiet.',
        if (result.style == ChartStyle.histogram)
          'Bin widths are equal and chosen from the number of values, so the '
              'shape is not an artefact of where the boundaries fall.',
        if (result.correlation != null)
          'The coefficient describes how closely the two move together. It '
              'says nothing about one causing the other, and a register is '
              'not an experiment.',
        ...result.caveats,
      ],
      derivation: <ExplainRow>[
        if (stats != null) ...<ExplainRow>[
          ExplainRow(label: 'Values used', value: '${stats.count}'),
          if (stats.missing > 0)
            ExplainRow(label: 'Missing', value: '${stats.missing}'),
          ExplainRow(label: 'Mean', value: _number(stats.mean)),
          ExplainRow(label: 'Median', value: _number(stats.median)),
          ExplainRow(
            label: 'Range',
            value: '${_number(stats.min)} – ${_number(stats.max)}',
          ),
          ExplainRow(label: 'Std deviation', value: _number(stats.sd)),
          ExplainRow(
            label: 'Middle half',
            value: '${_number(stats.q1)} – ${_number(stats.q3)}',
          ),
        ],
        if (result.correlation case final correlation?)
          ExplainRow(
            label: 'Correlation (r)',
            value: correlation.r.toStringAsFixed(2),
          ),
        if (result.trend case final trend?)
          ExplainRow(
            label: 'Trend per ${spec.bucket.label}',
            value: _number(trend.slopePerStep),
          ),
      ],
      total: _number(result.total),
      confidence: switch (_confidenceFrom(result)) {
        > 0.75 => ExplainConfidence.measured,
        > 0.45 => ExplainConfidence.heuristic,
        _ => ExplainConfidence.insufficientData,
      },
      caveat: result.rowsRead < _thinEvidence
          ? 'Only ${result.rowsRead} records went into this. That is too few '
              'to read a pattern from — treat it as a look at the data rather '
              'than a finding.'
          : 'It describes what was recorded, not what happened. A field left '
              'blank looks the same here as one that was never relevant.',
    );
  }

  static String _unitSuffix(AnalysisSpec spec) =>
      spec.aggregate == Aggregate.count || spec.measure?.unit == null
          ? ''
          : ' ${spec.measure!.unit}';

  static String _number(double value) => Fmt.stat(value);

  static String _titleCase(String value) => Fmt.titleCase(value);
}
