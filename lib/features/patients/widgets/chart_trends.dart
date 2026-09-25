import 'package:flutter/material.dart';

import '../../../clinical/insights/trend_analysis.dart';
import '../../../core/design/design.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/services/assist/assist_service.dart';
import '../patient_chart_controller.dart';

/// Vital-sign trends. Direction over time is often more informative than any
/// single reading — a pulse climbing 70 → 95 → 118 matters even while each
/// value is still inside its reference band.
///
/// Two layers, following the kit charts' overview-first structure:
///
///  * an [OptTrendGrid] of small multiples — the at-a-glance overview; a tap
///    opens the kit's [OptTrendDetail] (full line chart, min/mean/max, range
///    selector) in a sheet;
///  * the existing per-measure sparkline rows, which stay on the app's own
///    gap-aware [Sparkline]: a missing observation must render as a gap, and
///    the kit's [TrendSeries] model has no null-gap concept. The overview grid
///    plots recorded values only, so its shapes are unaffected by gaps.
class Trends extends StatelessWidget {
  const Trends({super.key, required this.chart});

  final PatientChartController chart;

  void _showDetail(BuildContext context, TrendSeries series) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final m = sheetContext.metrics;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceLg),
            child: OptTrendDetail(series: series),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Oldest first for plotting; the DAO returns newest first.
    final history = chart.vitals.reversed.toList();
    if (history.length < 2) return const SizedBox.shrink();

    final palette = context.palette;
    final m = context.metrics;

    final series = <({String label, List<double?> values, Color color})>[
      (
        label: 'Systolic BP',
        values: history.map((v) => v.systolicBp?.toDouble()).toList(),
        color: palette.primary,
      ),
      (
        label: 'Pulse',
        values: history.map((v) => v.heartRate?.toDouble()).toList(),
        color: palette.accent,
      ),
      (
        label: 'Temperature',
        values: history.map((v) => v.temperatureC).toList(),
        color: palette.caution,
      ),
      (
        label: 'Weight',
        values: history.map((v) => v.weightKg).toList(),
        color: palette.info,
      ),
    ].where((s) => s.values.whereType<double>().length >= 2).toList();

    if (series.isEmpty) return const SizedBox.shrink();

    // The same measures as kit series for the overview grid and detail sheet.
    // Recorded values only — the grid compares shapes, and the rows below keep
    // the gap-aware rendering for anything with missing observations.
    final overview = <TrendSeries>[
      for (final s in series)
        TrendSeries.fromValues(
          id: s.label,
          label: s.label,
          unit: switch (AssistService.unitFor(s.label)) {
            '' => null,
            final u => u,
          },
          values: s.values.whereType<double>().toList(),
        ),
    ];
    final tones = <String, Color>{for (final s in series) s.label: s.color};

    // The bottom margin lives inside the widget, next to the early returns
    // above: when Trends renders nothing it must contribute zero height, so
    // callers never place a spacer after it that could outlive the card.
    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceMd),
      child: SectionCard(
        title: 'Trends',
        subtitle: '${history.length} observation sets',
        leading: const Icon(Icons.show_chart, size: 20),
        child: Column(
          children: <Widget>[
            // The overview grid is demoted behind a collapsed header: at
            // glance-time the clinically-tuned sparkline rows below carry the
            // numeric+trend read, and the grid of small multiples is consulted
            // on demand. Collapsed costs zero body height, so the rows keep
            // their screen space. Tap a cell for the full detail chart.
            OptCollapsibleSection(
              title: 'Trends overview',
              initiallyExpanded: false,
              child: Padding(
                padding: EdgeInsets.only(top: m.spaceSm),
                child: OptTrendGrid(
                  series: overview,
                  statusColorOf: (s) => tones[s.id],
                  onTapSeries: (s) => _showDetail(context, s),
                ),
              ),
            ),
            SizedBox(height: m.spaceLg),
            for (final (i, s) in series.indexed)
              Padding(
                // Between rows only — the last row must not prop the card open
                // with a dead block of padding under it.
                padding: EdgeInsets.only(
                  bottom: i == series.length - 1 ? 0 : m.spaceMd,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 96,
                      child: Text(s.label, style: context.texts.labelSmall),
                    ),
                    Expanded(
                      child: Sparkline(values: s.values, color: s.color),
                    ),
                    SizedBox(width: m.spaceSm),
                    SizedBox(
                      width: 44,
                      child: Text(
                        Fmt.number(s.values.whereType<double>().last),
                        textAlign: TextAlign.right,
                        style: context.texts.labelMedium?.copyWith(
                          color: s.color,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Observations moving the wrong way.
///
/// This is the one panel in the chart that says something no single reading
/// can: a pulse of 70, then 95, then 118 is three defensible adult values and a
/// patient deteriorating in front of you. It is shown only when there is
/// something to show — a panel that usually reads "no concerns" is one that
/// stops being read, including on the day it matters.
class TrendAlerts extends StatelessWidget {
  const TrendAlerts({super.key, required this.trends});

  final List<TrendResult> trends;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Callout(
      title: trends.length == 1
          ? 'One observation is moving the wrong way'
          : '${trends.length} observations are moving the wrong way',
      icon: Icons.trending_up,
      tone: palette.caution,
      subtitle:
          'Direction across recorded visits — every reading may still be '
          'inside its reference band.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: const AiBadge(label: 'Detected', dense: true),
          ),
          for (final trend in trends)
            Padding(
              padding: EdgeInsets.only(top: m.spaceSm),
              child: Row(
                children: <Widget>[
                  Icon(
                    trend.direction == TrendDirection.rising
                        ? Icons.north_east
                        : Icons.south_east,
                    size: 15,
                    color: palette.caution,
                  ),
                  SizedBox(width: m.spaceSm),
                  Expanded(
                    child: Text(
                      '${trend.label} ${trend.direction.label} — '
                      '${trend.first.toStringAsFixed(0)} to '
                      '${trend.last.toStringAsFixed(0)} '
                      '${AssistService.unitFor(trend.label)} '
                      'over ${trend.points} readings',
                      style: context.texts.bodySmall,
                    ),
                  ),
                  InfoDot(
                    explanation: TrendAnalysis.explain(
                      trend,
                      AssistService.unitFor(trend.label),
                    ),
                    semanticLabel: 'How this trend was worked out',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
