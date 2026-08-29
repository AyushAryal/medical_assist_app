import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/data/services/ocr/table_reconstruction.dart';

void main() {
  OcrLine line(String t, double x, double y) =>
      OcrLine(text: t, x: x, y: y, w: 0.15, h: 0.03);

  test('single column of lines stays plain text, not a table', () {
    final md = reconstructMarkdown(<OcrLine>[
      line('Chief complaint', 0.1, 0.10),
      line('History', 0.1, 0.16),
      line('Plan', 0.1, 0.22),
    ]);
    expect(md, isNot(contains('|')));
    expect(md, 'Chief complaint\nHistory\nPlan');
  });

  test('a two-column grid becomes a Markdown table', () {
    // Two columns (x ~0.1 and ~0.6), three rows.
    final md = reconstructMarkdown(<OcrLine>[
      line('Test', 0.10, 0.10), line('Result', 0.60, 0.10),
      line('Sodium', 0.10, 0.18), line('140', 0.60, 0.18),
      line('Potassium', 0.10, 0.26), line('4.2', 0.60, 0.26),
    ]);
    final lines = md.split('\n');
    expect(lines.first, '| Test | Result |');
    expect(lines[1], '| --- | --- |');
    expect(md, contains('| Sodium | 140 |'));
    expect(md, contains('| Potassium | 4.2 |'));
  });

  test('cells landing in the same row are grouped by vertical position', () {
    // Slight y jitter within a row must still group as one row.
    final md = reconstructMarkdown(<OcrLine>[
      line('A', 0.10, 0.100), line('B', 0.60, 0.104),
      line('1', 0.10, 0.200), line('2', 0.60, 0.198),
    ]);
    // First row is the header, so: header + separator + one data row = 3.
    expect(md.split('\n').length, 3);
    expect(md, contains('| A | B |'));
    expect(md, contains('| 1 | 2 |'));
  });

  test('empty input yields empty string', () {
    expect(reconstructMarkdown(const <OcrLine>[]), '');
  });
}
