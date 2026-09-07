import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import 'chart_section.dart';

extension ChartSectionX on ChartSection {
  String get label => switch (this) {
        ChartSection.summary => 'Summary',
        ChartSection.history => 'History',
        ChartSection.observations => 'Observations',
        ChartSection.files => 'Files',
      };

  IconData get icon => switch (this) {
        ChartSection.summary => Icons.badge_outlined,
        ChartSection.history => Icons.history_outlined,
        ChartSection.observations => Icons.show_chart,
        ChartSection.files => Icons.folder_outlined,
      };
}

/// Moves between the four parts of the chart.
class ChartSectionSwitcher extends StatelessWidget {
  const ChartSectionSwitcher({
    super.key,
    required this.section,
    required this.onChanged,
    required this.visitCount,
    required this.fileCount,
  });

  final ChartSection section;
  final ValueChanged<ChartSection> onChanged;
  final int visitCount;
  final int fileCount;

  String _label(ChartSection value) => switch (value) {
        ChartSection.history when visitCount > 0 =>
          '${value.label} ($visitCount)',
        ChartSection.files when fileCount > 0 => '${value.label} ($fileCount)',
        _ => value.label,
      };

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: m.spaceLg,
        vertical: m.spaceSm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: palette.outline, width: m.hairline),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final value in ChartSection.values)
              Padding(
                padding: EdgeInsets.only(right: m.spaceSm),
                child: ChoiceChip(
                  selected: value == section,
                  showCheckmark: false,
                  avatar: Icon(
                    value.icon,
                    size: 16,
                    color: value == section
                        ? palette.onPrimaryContainer
                        : palette.onSurfaceMuted,
                  ),
                  label: Text(_label(value)),
                  onSelected: (_) => onChanged(value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
