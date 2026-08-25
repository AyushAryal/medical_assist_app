import 'package:flutter/material.dart';

import '../../../ai/presentation.dart';
import '../../../core/design/design.dart';

/// Switches one answer between its honest renderings.
///
/// Icons only, sized to sit inside the heading row: this is a preference, not
/// a navigation, and it must not compete with the headline it sits beside. It
/// renders nothing at all when there is only one view — a toggle with one
/// position is furniture.
class ViewToggle extends StatelessWidget {
  const ViewToggle({
    super.key,
    required this.views,
    required this.current,
    required this.onChanged,
  });

  final List<ResultView> views;
  final ResultView current;
  final ValueChanged<ResultView> onChanged;

  static IconData iconFor(ResultView view) => switch (view) {
        ResultView.list => Icons.view_agenda_outlined,
        ResultView.table => Icons.table_rows_outlined,
        ResultView.chart => Icons.insert_chart_outlined,
      };

  static String labelFor(ResultView view) => switch (view) {
        ResultView.list => 'As a list',
        ResultView.table => 'As a table',
        ResultView.chart => 'As a chart',
      };

  @override
  Widget build(BuildContext context) {
    if (views.length < 2) return const SizedBox.shrink();
    final palette = context.palette;
    final m = context.metrics;

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final view in views)
            Tooltip(
              message: labelFor(view),
              child: InkWell(
                onTap: () => onChanged(view),
                borderRadius: BorderRadius.circular(m.radiusXs),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: m.spaceSm,
                    vertical: m.spaceXs / 2,
                  ),
                  decoration: BoxDecoration(
                    color: view == current ? palette.surface : null,
                    borderRadius: BorderRadius.circular(m.radiusXs),
                    boxShadow: view == current
                        ? <BoxShadow>[
                            BoxShadow(
                              color: palette.shadow.withValues(alpha: 0.12),
                              blurRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    iconFor(view),
                    size: 15,
                    color: view == current
                        ? palette.primary
                        : palette.onSurfaceMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
