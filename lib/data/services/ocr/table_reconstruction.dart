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

/// Rebuilds page layout from recognised line boxes as a *mix* of prose and
/// tables — only the parts that are genuinely laid out in columns become
/// Markdown tables; everything else stays plain text.
///
/// Deterministic geometry, not a model. Most of a page (a letterhead, a
/// paragraph, a signed section) is not a table, and forcing it into one is
/// worse than leaving it alone — so a run only becomes a table when several
/// *consecutive* rows share aligned multi-column structure. Everything outside
/// such a run is emitted as prose.
String reconstructMarkdown(List<OcrLine> lines) {
  if (lines.isEmpty) return '';
  final rows = _rows(lines);

  final heights = lines.map((l) => l.h).toList()..sort();
  final medianH = heights[heights.length ~/ 2];

  // The document's normal line pitch — the baseline a break is measured
  // against, so ordinary single-spaced text is not chopped into paragraphs.
  final rowCys = rows.map((r) => r.first.cy).toList();
  final pitches = <double>[
    for (var k = 1; k < rowCys.length; k++) rowCys[k] - rowCys[k - 1],
  ]..sort();
  final normalGap = pitches.isEmpty ? double.infinity : pitches[pitches.length ~/ 2];

  final out = <String>[];
  double? prevCy;
  var i = 0;
  while (i < rows.length) {
    final run = _tableRun(rows, i);
    if (run.length >= 2) {
      if (out.isNotEmpty) out.add('');
      out.add(_tableMarkdown(run));
      out.add('');
      prevCy = run.last.first.cy;
      i += run.length;
      continue;
    }

    final row = rows[i];
    final cy = row.first.cy;
    // A large vertical gap is a section break; a moderate one is a paragraph
    // break. (medianH is a line height, so gaps are measured in lines.)
    if (prevCy != null) {
      final gap = cy - prevCy;
      if (gap > normalGap * 2.3) {
        out..add('')..add('---')..add('');
      } else if (gap > normalGap * 1.5) {
        out.add('');
      }
    }

    // Relative text size marks a heading — the only formatting the geometry can
    // tell us honestly (Vision gives no font weight, so bold/italic are never
    // guessed).
    final rowH = row.map((l) => l.h).reduce(math.max);
    final prefix = rowH >= medianH * 1.6
        ? '# '
        : rowH >= medianH * 1.28
            ? '## '
            : '';
    out.add('$prefix${row.map((l) => l.text).join(' ')}');
    prevCy = cy;
    i++;
  }

  // Collapse runs of blank lines and trim.
  final cleaned = <String>[];
  for (final line in out) {
    if (line.isEmpty && (cleaned.isEmpty || cleaned.last.isEmpty)) continue;
    cleaned.add(line);
  }
  return cleaned.join('\n').trim();
}

/// Groups lines into rows by vertical proximity; each row is sorted left→right.
List<List<OcrLine>> _rows(List<OcrLine> lines) {
  final sorted = <OcrLine>[...lines]..sort((a, b) => a.cy.compareTo(b.cy));
  final heights = sorted.map((l) => l.h).toList()..sort();
  final medianH = heights[heights.length ~/ 2];
  final gap = math.max(medianH * 0.6, 0.006);

  final rows = <List<OcrLine>>[];
  var current = <OcrLine>[sorted.first];
  for (final line in sorted.skip(1)) {
    if ((line.cy - current.last.cy).abs() <= gap) {
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
  return rows;
}

/// How far (normalised) a cell centre may sit from a column centre and still
/// count as that column.
const double _columnTolerance = 0.08;

/// The consecutive rows starting at [start] that form one aligned table. Length
/// 1 (or 0) means "not a table here".
List<List<OcrLine>> _tableRun(List<List<OcrLine>> rows, int start) {
  final first = rows[start];
  if (first.length < 2) return <List<OcrLine>>[first];

  final centres = first.map((l) => l.cx).toList();
  final run = <List<OcrLine>>[first];
  for (var j = start + 1; j < rows.length; j++) {
    final row = rows[j];
    if (row.length < 2 || row.length > centres.length) break;
    if (!_alignsTo(row, centres)) break;
    run.add(row);
  }
  return run;
}

/// Every cell in [row] sits within tolerance of one of the [centres].
bool _alignsTo(List<OcrLine> row, List<double> centres) {
  for (final cell in row) {
    var nearest = double.infinity;
    for (final c in centres) {
      nearest = math.min(nearest, (cell.cx - c).abs());
    }
    if (nearest > _columnTolerance) return false;
  }
  return true;
}

String _tableMarkdown(List<List<OcrLine>> run) {
  final centres = run.first.map((l) => l.cx).toList();
  final cols = centres.length;

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

  final grid = run.map(toCells).toList();
  final buffer = StringBuffer()
    ..writeln('| ${grid.first.join(' | ')} |')
    ..writeln('| ${List<String>.filled(cols, '---').join(' | ')} |');
  for (final row in grid.skip(1)) {
    buffer.writeln('| ${row.join(' | ')} |');
  }
  return buffer.toString().trimRight();
}
