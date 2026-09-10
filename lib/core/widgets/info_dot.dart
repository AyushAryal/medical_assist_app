import 'package:flutter/material.dart';

import '../../clinical/explanations.dart';
import '../theme/theme_config.dart';
import '../theme/theme_scope.dart';
import 'glass.dart';

/// The small circled "i" that sits beside anything the app worked out for
/// itself.
///
/// Sized to the surrounding text rather than to a standard icon button: this is
/// punctuation on a label, not an action competing with it. The tap target is
/// still expanded to the minimum comfortable size, because a 14px hit box is
/// unusable with a gloved thumb.
class InfoDot extends StatelessWidget {
  const InfoDot({super.key, required this.explanation, this.semanticLabel});

  /// Convenience for prose that needs no derivation — a definition rather than
  /// a calculation.
  InfoDot.text({
    super.key,
    required String title,
    required String summary,
    List<String> method = const <String>[],
    String? source,
    String? caveat,
    ExplainConfidence confidence = ExplainConfidence.measured,
    this.semanticLabel,
  }) : explanation = MetricExplanation(
         title: title,
         summary: summary,
         method: method,
         source: source,
         caveat: caveat,
         confidence: confidence,
       );

  final MetricExplanation explanation;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      label: semanticLabel ?? 'How ${explanation.title} is worked out',
      child: InkResponse(
        onTap: () => ExplainSheet.show(context, explanation),
        radius: 18,
        containedInkWell: false,
        child: Padding(
          // Brings the hit box up to a usable size without changing how the
          // mark reads next to the label.
          padding: const EdgeInsets.all(6),
          child: Icon(
            Icons.info_outline,
            size: 15,
            color: palette.onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}

/// A label with its explanation attached — the pairing used throughout the app
/// so a derived figure never appears without a way to interrogate it.
class ExplainedLabel extends StatelessWidget {
  const ExplainedLabel({
    super.key,
    required this.label,
    required this.explanation,
    this.style,
  });

  final String label;
  final MetricExplanation explanation;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: style ?? context.texts.labelLarge),
        InfoDot(explanation: explanation),
      ],
    );
  }
}

/// The sheet an [InfoDot] opens: what the number means, how it was reached,
/// the inputs that produced it, and what it cannot be trusted to say.
class ExplainSheet extends StatelessWidget {
  const ExplainSheet({super.key, required this.explanation});

  final MetricExplanation explanation;

  static Future<void> show(
    BuildContext context,
    MetricExplanation explanation,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ExplainSheet(explanation: explanation),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final e = explanation;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          maxWidth: m.contentMaxWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Pinned above the scroll: a sheet tall enough to fill the screen
            // reads as a page, and a page needs a visible way out — the drag
            // handle alone was being missed, and a drag on the content scrolls
            // rather than dismisses.
            Padding(
              padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceSm, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(e.title, style: context.texts.titleLarge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  m.spaceLg,
                  0,
                  m.spaceLg,
                  m.spaceXl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(e.summary, style: context.texts.bodyMedium),
                    SizedBox(height: m.spaceLg),
                    _ConfidenceStrip(confidence: e.confidence),
                    if (e.method.isNotEmpty) ...<Widget>[
                      SizedBox(height: m.spaceLg),
                      Text(
                        'How it is worked out',
                        style: context.texts.labelLarge,
                      ),
                      SizedBox(height: m.spaceSm),
                      for (var i = 0; i < e.method.length; i++)
                        _Step(index: i + 1, text: e.method[i]),
                    ],
                    if (e.hasDerivation) ...<Widget>[
                      SizedBox(height: m.spaceLg),
                      Text('For this record', style: context.texts.labelLarge),
                      SizedBox(height: m.spaceSm),
                      _DerivationTable(rows: e.derivation, total: e.total),
                    ] else if (e.total != null) ...<Widget>[
                      SizedBox(height: m.spaceLg),
                      Text('Result', style: context.texts.labelLarge),
                      SizedBox(height: m.spaceXs),
                      Text(e.total!, style: context.texts.titleMedium),
                    ],
                    if (e.caveat != null) ...<Widget>[
                      SizedBox(height: m.spaceLg),
                      Container(
                        padding: EdgeInsets.all(m.spaceMd),
                        decoration: BoxDecoration(
                          color: palette.caution.withValues(
                            alpha: context.isDark ? 0.14 : 0.09,
                          ),
                          borderRadius: BorderRadius.circular(m.radiusSm),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              Icons.error_outline,
                              size: 17,
                              color: palette.caution,
                            ),
                            SizedBox(width: m.spaceSm),
                            Expanded(
                              child: Text(
                                e.caveat!,
                                style: context.texts.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (e.source != null) ...<Widget>[
                      SizedBox(height: m.spaceLg),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.menu_book_outlined,
                            size: 15,
                            color: palette.onSurfaceMuted,
                          ),
                          SizedBox(width: m.spaceSm),
                          Expanded(
                            child: Text(
                              e.source!,
                              style: context.texts.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceStrip extends StatelessWidget {
  const _ConfidenceStrip({required this.confidence});

  final ExplainConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    final (Color tone, IconData icon) = switch (confidence) {
      ExplainConfidence.measured => (palette.info, Icons.calculate_outlined),
      ExplainConfidence.validated => (palette.normal, Icons.verified_outlined),
      ExplainConfidence.heuristic => (palette.caution, Icons.lightbulb_outline),
      ExplainConfidence.insufficientData => (
        palette.onSurfaceMuted,
        Icons.data_usage_outlined,
      ),
    };

    return Container(
      padding: EdgeInsets.all(m.spaceMd),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
        border: Border.all(color: palette.outline, width: m.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: tone),
          SizedBox(width: m.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  confidence.label,
                  style: context.texts.labelMedium?.copyWith(color: tone),
                ),
                SizedBox(height: m.spaceXs / 2),
                Text(confidence.meaning, style: context.texts.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: context.texts.labelSmall?.copyWith(
                color: palette.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: m.spaceSm),
          Expanded(child: Text(text, style: context.texts.bodyMedium)),
        ],
      ),
    );
  }
}

/// The inputs, their contributions, and the total they add up to.
class _DerivationTable extends StatelessWidget {
  const _DerivationTable({required this.rows, this.total});

  final List<ExplainRow> rows;
  final String? total;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return GlassPanel(
      padding: EdgeInsets.symmetric(horizontal: m.spaceMd, vertical: m.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0)
              Divider(
                height: m.spaceMd,
                thickness: m.hairline,
                color: palette.outline,
              ),
            _DerivationLine(row: rows[i]),
          ],
          if (total != null) ...<Widget>[
            Divider(
              height: m.spaceMd,
              thickness: m.hairline,
              color: palette.outline,
            ),
            Row(
              children: <Widget>[
                Expanded(child: Text('Total', style: context.texts.labelLarge)),
                Text(
                  total!,
                  style: context.texts.titleSmall?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DerivationLine extends StatelessWidget {
  const _DerivationLine({required this.row});

  final ExplainRow row;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(row.label, style: context.texts.labelMedium),
              Text(row.value, style: context.texts.bodySmall),
              if (row.note != null)
                Text(
                  row.note!,
                  style: context.texts.labelSmall?.copyWith(
                    color: palette.onSurfaceMuted,
                  ),
                ),
            ],
          ),
        ),
        if (row.contribution != null) ...<Widget>[
          SizedBox(width: m.spaceSm),
          Text(
            row.contribution!,
            style: context.texts.titleSmall?.copyWith(
              color: _contributionTone(palette, row.contribution!),
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }

  /// A zero contribution is quiet; anything that pushed the total up is not.
  static Color _contributionTone(ClinicalPalette palette, String contribution) {
    if (contribution == '+0' || contribution == '0') {
      return palette.onSurfaceMuted;
    }
    final magnitude = int.tryParse(contribution.replaceAll('+', ''));
    if (magnitude != null && magnitude >= 3) return palette.critical;
    if (magnitude != null && magnitude >= 2) return palette.caution;
    return palette.onSurface;
  }
}
