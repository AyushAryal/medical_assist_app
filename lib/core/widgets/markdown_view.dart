import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// A small Markdown renderer for the app's own needs: pipe tables, bullet
/// lists and paragraphs. Not a full Markdown engine — just enough that a table
/// (from OCR layout reconstruction or a generated draft) renders as a table
/// rather than a wall of pipes, and everything else reads as plain text.
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data, this.style});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? context.texts.bodyMedium;
    final lines = data.split('\n');
    final blocks = <Widget>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];
      if (_isTableRow(line)) {
        final table = <String>[];
        while (i < lines.length && _isTableRow(lines[i])) {
          table.add(lines[i]);
          i++;
        }
        blocks.add(_table(context, table, base));
        continue;
      }
      if (line.trim().isEmpty) {
        blocks.add(SizedBox(height: context.metrics.spaceSm));
        i++;
        continue;
      }
      blocks.add(SelectableText(_stripBullet(line), style: base));
      i++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  static bool _isTableRow(String line) {
    final t = line.trim();
    return t.startsWith('|') && t.contains('|', 1);
  }

  static bool _isSeparator(List<String> cells) =>
      cells.isNotEmpty &&
      cells.every((c) => c.trim().isNotEmpty && RegExp(r'^:?-{2,}:?$').hasMatch(c.trim()));

  List<String> _cells(String row) {
    var t = row.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((c) => c.replaceAll(r'\|', '|').trim()).toList();
  }

  Widget _table(BuildContext context, List<String> rows, TextStyle? base) {
    final palette = context.palette;
    final parsed = rows.map(_cells).where((c) => !_isSeparator(c)).toList();
    if (parsed.isEmpty) return const SizedBox.shrink();
    final cols = parsed.fold<int>(0, (mx, r) => r.length > mx ? r.length : mx);

    List<Widget> cellsFor(List<String> cells, bool header) => <Widget>[
          for (var c = 0; c < cols; c++)
            Padding(
              padding: EdgeInsets.all(context.metrics.spaceXs + 1),
              child: Text(
                c < cells.length ? cells[c] : '',
                style: base?.copyWith(
                  fontWeight: header ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
        ];

    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.metrics.spaceXs),
      child: Table(
        border: TableBorder.all(
          color: palette.outline.withValues(alpha: 0.5),
          width: 1,
        ),
        defaultColumnWidth: const FlexColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: <TableRow>[
          for (var r = 0; r < parsed.length; r++)
            TableRow(
              decoration: r == 0
                  ? BoxDecoration(color: palette.surfaceMuted)
                  : null,
              children: cellsFor(parsed[r], r == 0),
            ),
        ],
      ),
    );
  }

  static String _stripBullet(String line) {
    final t = line.trimLeft();
    if (t.startsWith('- ') || t.startsWith('* ')) return '•  ${t.substring(2)}';
    return line;
  }
}
