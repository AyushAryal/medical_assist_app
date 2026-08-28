import 'package:flutter/material.dart';

import '../../theme/theme_scope.dart';
import 'ai_shimmer.dart';

/// Placeholder lines that shimmer while text is being produced.
///
/// Shown instead of a spinner because it previews the *shape* of what is
/// coming. A spinner says "wait"; this says "paragraphs of text are on their
/// way", which is the honest signal when transcription takes longer than the
/// recording did.
class AiTextPlaceholder extends StatelessWidget {
  const AiTextPlaceholder({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return AiShimmer(
      active: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < lines; i++)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceSm),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                // A ragged right edge reads as prose; equal bars read as a
                // loading skeleton for a table.
                widthFactor: i == lines - 1 ? 0.55 : (i.isEven ? 0.95 : 0.8),
                child: Container(
                  height: 11,
                  decoration: BoxDecoration(
                    color: palette.onSurfaceMuted.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(m.radiusXs),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
