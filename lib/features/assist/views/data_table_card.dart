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
    this.caption,
    this.captionIcon = Icons.table_rows_outlined,
    this.leading,
    this.onTapRow,
    this.footer,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final String? title;

  /// Provenance metadata ("Donut chart · 8 rows read · from 17 Jun") rather
  /// than a name. Drawn as one quiet line that truncates, where [title] is a
  /// heading that wraps — a caption set as the title dominated the card.
  final String? caption;

  /// Glyph for the caption line.
  final IconData captionIcon;

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
      leading: title == null
          ? null
          : leading ?? const Icon(Icons.table_rows_outlined, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (caption != null) ...<Widget>[
            AnswerCaption(text: caption!, icon: captionIcon),
            SizedBox(height: m.spaceSm),
          ],
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

/// One quiet, truncating line of provenance metadata at the top of an answer
/// card — how the figure was drawn, from how many rows, since when.
class AnswerCaption extends StatelessWidget {
  const AnswerCaption({super.key, required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: palette.onSurfaceMuted),
        SizedBox(width: context.metrics.spaceSm),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.labelMedium?.copyWith(
              color: palette.onSurfaceMuted,
            ),
          ),
        ),
      ],
    );
  }
}
