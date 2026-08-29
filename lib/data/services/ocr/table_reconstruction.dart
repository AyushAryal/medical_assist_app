import 'dart:math' as math;

/// A recognised line with its normalised box (0–1, top-left origin).
class OcrLine {
  const OcrLine({
    required this.text,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final String text;
  final double x, y, w, h;

  double get cx => x + w / 2;
  double get cy => y + h / 2;
}

/// Rebuilds layout from recognised line boxes: a Markdown table when the text
/// is laid out in columns, plain lines otherwise.
///
/// Deterministic geometry, not a model — it groups boxes into rows by vertical
/// position and into columns by horizontal position, so a table on the page
/// stays a table rather than collapsing into one run-on stream. Conservative:
/// it only emits a table when the layout clearly is one, and always leaves
/// readable text behind when it is not.
String reconstructMarkdown(List<OcrLine> lines) {
  if (lines.isEmpty) return '';
  final sorted = <OcrLine>[...lines]..sort((a, b) => a.cy.compareTo(b.cy));

  final heights = sorted.map((l) => l.h).toList()..sort();
  final medianH = heights[heights.length ~/ 2];
  final rowGap = math.max(medianH * 0.7, 0.008);

  // Group into rows by vertical proximity.
  final rows = <List<OcrLine>>[];
  var current = <OcrLine>[sorted.first];
  for (final line in sorted.skip(1)) {
    if ((line.cy - current.last.cy).abs() <= rowGap) {
      current.add(line);
    } else {
      rows.add(current);
      current = <OcrLine>[line];
    }
  }
  rows.add(current);
  for (final row in rows) {
    row.sort((a, b) => a.cx.compareTo(b.cx));
  }

  final cols = rows.fold<int>(0, (mx, r) => math.max(mx, r.length));
  final multiCellRows = rows.where((r) => r.length >= 2).length;
  final looksTabular = rows.length >= 2 && cols >= 2 && multiCellRows >= 2;

  if (!looksTabular) {
    return rows.map((r) => r.map((l) => l.text).join(' ')).join('\n');
  }

  // Column centres come from the widest row; each cell joins the nearest column.
  final anchor = rows.firstWhere((r) => r.length == cols);
  final centres = anchor.map((l) => l.cx).toList();

  List<String> toCells(List<OcrLine> row) {
    final cells = List<String>.filled(cols, '');
    for (final line in row) {
      var best = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < cols; i++) {
        final d = (line.cx - centres[i]).abs();
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      final safe = line.text.replaceAll('|', r'\|').trim();
      cells[best] = cells[best].isEmpty ? safe : '${cells[best]} $safe';
    }
    return cells;
  }

  final grid = rows.map(toCells).toList();
  final buffer = StringBuffer()
    ..writeln('| ${grid.first.join(' | ')} |')
    ..writeln('| ${List<String>.filled(cols, '---').join(' | ')} |');
  for (final row in grid.skip(1)) {
    buffer.writeln('| ${row.join(' | ')} |');
  }
  return buffer.toString().trimRight();
}
