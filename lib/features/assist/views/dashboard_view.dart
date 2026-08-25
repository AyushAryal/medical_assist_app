import 'package:flutter/material.dart';

import '../../../ai/presentation.dart';
import '../../../core/design/design.dart';

/// Several answers on one canvas.
///
/// Each tile is an ordinary presentation rendered by the ordinary renderer —
/// handed in as a builder so this file does not need to know how rendering
/// works, only how tiles are arranged. On a wide screen the tiles flow into
/// columns; in the bubble they stack, because a grid squeezed into 340px is
/// four unreadable charts instead of one readable one.
class DashboardAnswerView extends StatelessWidget {
  const DashboardAnswerView({
    super.key,
    required this.result,
    required this.compact,
    required this.panelBuilder,
  });

  final DashboardPresentation result;
  final bool compact;

  /// Renders one panel's presentation the way any lone answer is rendered.
  final Widget Function(Presentation body) panelBuilder;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    final tiles = <Widget>[
      for (final panel in result.panels)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceXs, left: m.spaceXs),
              child: Text(panel.title, style: context.texts.labelLarge),
            ),
            panelBuilder(panel.body),
          ],
        ),
    ];

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final tile in tiles)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceMd),
              child: tile,
            ),
        ],
      );
    }

    // Two columns once there is room for two readable charts side by side.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 2 : 1;
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final tile in tiles)
                Padding(
                  padding: EdgeInsets.only(bottom: m.spaceMd),
                  child: tile,
                ),
            ],
          );
        }
        final width = (constraints.maxWidth - m.spaceMd) / 2;
        return Wrap(
          spacing: m.spaceMd,
          runSpacing: m.spaceMd,
          children: <Widget>[
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}
