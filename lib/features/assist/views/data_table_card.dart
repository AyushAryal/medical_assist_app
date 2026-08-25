import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

/// The one way a table is drawn in an answer.
///
/// Three views need a table — a projection over patients, the numbers behind
/// a chart, and a `TablePresentation` of its own — and if each drew its own,
/// column spacing, row heights and overflow behaviour would drift the way the
/// bubble and the page once did. Wide content scrolls inside its own box
/// rather than making the page scroll sideways.
class AnswerTableCard extends StatelessWidget {
  const AnswerTableCard({
    super.key,
    required this.columns,
    required this.rows,
    this.title,
    this.leading,
    this.onTapRow,
    this.footer,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final String? title;
  final Widget? leading;

  /// Row index → action. Set where a row stands for a record that can be
  /// opened; a table of people you cannot tap is a dead end with columns.
  final ValueChanged<int>? onTapRow;

  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SectionCard(
      title: title,
      leading: leading ?? const Icon(Icons.table_rows_outlined, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: m.spaceLg,
              headingRowHeight: 36,
              dataRowMinHeight: 34,
              dataRowMaxHeight: 44,
              showCheckboxColumn: false,
              columns: <DataColumn>[
                for (final column in columns)
                  DataColumn(
                    label: Text(column, style: context.texts.labelMedium),
                  ),
              ],
              rows: <DataRow>[
                for (var i = 0; i < rows.length; i++)
                  DataRow(
                    onSelectChanged: onTapRow == null
                        ? null
                        : (_) => onTapRow!(i),
                    cells: <DataCell>[
                      for (final cell in rows[i])
                        DataCell(
                          Text(cell, style: context.texts.bodySmall),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          ?footer,
        ],
      ),
    );
  }
}
