import 'package:flutter/material.dart';

import '../../../ai/analytics/analysis.dart';
import '../../../ai/analytics/statistics.dart';
import '../../../ai/presentation.dart';
import '../../../core/design/design.dart';
import '../../../core/utils/formatters.dart';
import 'data_table_card.dart';
import 'support.dart';

/// A series, drawn or tabulated.
///
/// The same points render both ways — the chart answers "what is the shape",
/// the table answers "what exactly are the values" — and the person reading is
/// the only one who knows which question they are asking, so the choice is a
/// toggle rather than a decision made for them.
class ChartAnswerView extends StatelessWidget {
  const ChartAnswerView({
    super.key,
    required this.result,
    required this.view,
    required this.compact,
    required this.rowLimit,
  });

  final ChartPresentation result;
  final ResultView view;
  final bool compact;
  final int rowLimit;

  @override
  Widget build(BuildContext context) {
    if (result.isEmpty) {
      return const SectionCard(
        child: EmptyState(
          icon: Icons.bar_chart_outlined,
          title: 'Nothing recorded in that period',
          compact: true,
        ),
      );
    }
    return view == ResultView.table ? _table(context) : _chart(context);
  }

  Widget _table(BuildContext context) {
    final hasCounts =
        result.unit != null && result.points.any((p) => p.n > 1);

    return AnswerTableCard(
      title: result.caption,
      leading: Icon(DataChart.iconFor(result.style), size: 20),
      columns: <String>[
        result.axisLabel ?? 'Group',
        result.valueLabel ?? 'Value',
        // The row count only earns a column beside a derived figure; beside a
        // count it would repeat the number it sits next to.
        if (hasCounts) 'Records',
      ],
      rows: <List<String>>[
        for (final point in result.points)
          <String>[
            point.label,
            Fmt.stat(point.value, unit: result.unit, missing: 'not recorded'),
            if (hasCounts) '${point.n}',
          ],
      ],
      footer: result.footnotes.isEmpty || compact
          ? null
          : Padding(
              padding: EdgeInsets.only(top: context.metrics.spaceSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final note in result.footnotes) FootnoteLine(note),
                ],
              ),
            ),
    );
  }

  Widget _chart(BuildContext context) {
    final m = context.metrics;

    return SectionCard(
      title: result.caption,
      leading: Icon(DataChart.iconFor(result.style), size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (result.valueLabel case final label?)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceXs),
              child: Text(
                result.unit == null ? label : '$label (${result.unit})',
                style: context.texts.labelSmall?.copyWith(
                  color: context.palette.onSurfaceMuted,
                ),
              ),
            ),
          DataChart(
            style: result.style,
            points: result.points,
            unit: result.unit,
            compact: compact,
          ),
          if (result.stats case final stats?)
            if (!compact && _showsSpread) ...<Widget>[
              SizedBox(height: m.spaceSm),
              _SpreadPanel(stats: stats, result: result),
            ],
          if (result.footnotes.isNotEmpty && !compact) ...<Widget>[
            SizedBox(height: m.spaceSm),
            for (final note in result.footnotes) FootnoteLine(note),
          ],
        ],
      ),
    );
  }

  /// Only where the spread says something the chart does not.
  ///
  /// On a count it says nothing — the values *are* the counts, and their
  /// standard deviation is a fact about the bars rather than about any
  /// patient.
  bool get _showsSpread =>
      result.style == ChartStyle.histogram ||
      result.style == ChartStyle.scatter ||
      result.unit != null;
}

/// The statistics behind the picture.
class _SpreadPanel extends StatelessWidget {
  const _SpreadPanel({required this.stats, required this.result});

  final Stats stats;
  final ChartPresentation result;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final unit = result.unit == null ? '' : ' ${result.unit}';

    String n(double value) => Fmt.stat(value);

    return Container(
      padding: EdgeInsets.all(m.spaceSm),
      decoration: BoxDecoration(
        color: context.palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Across ${stats.count} values',
                  style: context.texts.labelSmall,
                ),
              ),
              if (stats.missing > 0)
                Text(
                  '${stats.missing} not recorded',
                  style: context.texts.labelSmall?.copyWith(
                    color: context.palette.caution,
                  ),
                ),
            ],
          ),
          SizedBox(height: m.spaceXs),
          Wrap(
            spacing: m.spaceMd,
            runSpacing: m.spaceXs / 2,
            children: <Widget>[
              _stat(context, 'Mean', '${n(stats.mean)}$unit'),
              _stat(context, 'Median', '${n(stats.median)}$unit'),
              _stat(
                  context, 'Middle half', '${n(stats.q1)}–${n(stats.q3)}$unit'),
              _stat(context, 'Range', '${n(stats.min)}–${n(stats.max)}$unit'),
              _stat(context, 'SD', n(stats.sd)),
              if (result.correlation case final correlation?)
                _stat(context, 'r', correlation.r.toStringAsFixed(2)),
            ],
          ),
          if (result.trend case final trend?)
            if (!trend.isFlat) ...<Widget>[
              SizedBox(height: m.spaceXs),
              Text(
                'Trending ${trend.direction} by about '
                '${n(trend.slopePerStep.abs())}$unit each step.',
                style: context.texts.labelSmall?.copyWith(
                  color: context.palette.onSurfaceMuted,
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$label ',
            style: context.texts.labelSmall?.copyWith(
              color: context.palette.onSurfaceMuted,
            ),
          ),
          Text(
            value,
            style: context.texts.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}
