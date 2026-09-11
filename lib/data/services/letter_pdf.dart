import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Renders a clinical letter as an A4 PDF in the conventional shape: practice
/// letterhead, date, a boxed patient-identification block, subject line,
/// salutation, the body, and a signature block.
///
/// Deterministic layout over caller-supplied text — the model never touches
/// the letterhead, the patient block or the signature, so whatever the draft
/// says, the letter is always attributed to the real clinician at the real
/// clinic, about an unambiguous patient.
///
/// Who a letter is addressed to — chosen by the clinician, never generated.
class LetterRecipient {
  const LetterRecipient({required this.name, this.clinic, this.specialty});

  final String name;
  final String? clinic;
  final String? specialty;

  /// "Dear Dr Sharma," — falls back to the neutral form when unset.
  String get salutation => 'Dear $name,';

  List<String> get addressLines => <String>[
        name,
        if (specialty != null && specialty!.trim().isNotEmpty) specialty!,
        if (clinic != null && clinic!.trim().isNotEmpty) clinic!,
      ];
}

/// The body is treated as Markdown at the block level (headings, bullets,
/// numbered lists, bold/italic), so what the clinician formats in the app is
/// what prints.
class LetterPdf {
  const LetterPdf({
    required this.title,
    required this.clinicianName,
    this.clinicName,
    this.patientName,
    this.patientDetails = const <String>[],
  });

  final String title;
  final String clinicianName;
  final String? clinicName;

  /// Who the letter is about. Rendered in the identification block, never
  /// taken from the generated text.
  final String? patientName;

  /// Identity lines under the name — age/sex, MRN, contact.
  final List<String> patientDetails;

  static const PdfColor _ink = PdfColor.fromInt(0xFF111827);
  static const PdfColor _muted = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _rule = PdfColor.fromInt(0xFF9CA3AF);

  /// The base-14 PDF fonts cover Latin-1 only; typographic characters outside
  /// it (em dash, curly quotes, ellipsis) print as tofu boxes. Mapped to their
  /// Latin-1 equivalents rather than embedding a font, which would grow every
  /// letter by hundreds of kilobytes.
  static String _latin1Safe(String text) => text
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('…', '...')
      .replaceAll('•', '-');

  Future<Uint8List> render(String body, {LetterRecipient? recipient}) async {
    body = _latin1Safe(body);
    final title = _latin1Safe(this.title);
    final clinicName =
        this.clinicName == null ? null : _latin1Safe(this.clinicName!);
    final clinicianName = _latin1Safe(this.clinicianName);
    final patientName =
        this.patientName == null ? null : _latin1Safe(this.patientName!);
    final patientDetails =
        this.patientDetails.map(_latin1Safe).toList(growable: false);
    final doc = pw.Document(title: title);
    final now = DateTime.now();

    const base = pw.TextStyle(fontSize: 10.5, color: _ink, lineSpacing: 2.5);
    final mutedSmall = pw.TextStyle(fontSize: 9, color: _muted);

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 64, vertical: 52),
          // Painted paper, not assumed paper: a PDF page has no background of
          // its own, so a raster of it is transparent — which on a dark
          // screen shows the letter as ink on nothing.
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: PdfColors.white),
          ),
        ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                patientName == null ? title : '$title - $patientName',
                style: mutedSmall,
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: mutedSmall,
              ),
            ],
          ),
        ),
        build: (context) => <pw.Widget>[
          // ---- Letterhead ------------------------------------------------
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(
                      clinicName ?? clinicianName,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    if (clinicName != null)
                      pw.Text(clinicianName,
                          style: const pw.TextStyle(fontSize: 10.5)),
                  ],
                ),
              ),
              pw.Text(
                DateFormat('d MMMM yyyy').format(now),
                style: const pw.TextStyle(fontSize: 10.5),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1, color: _rule, height: 1),
          pw.SizedBox(height: 18),

          // ---- Addressee -------------------------------------------------
          if (recipient != null) ...<pw.Widget>[
            for (final line in recipient.addressLines)
              pw.Text(_latin1Safe(line), style: base),
            pw.SizedBox(height: 14),
          ],

          // ---- Patient identification block ------------------------------
          if (patientName != null) ...<pw.Widget>[
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _rule, width: 0.7),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text('Re: $patientName',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      )),
                  for (final line in patientDetails)
                    pw.Text(line, style: base),
                ],
              ),
            ),
            pw.SizedBox(height: 18),
          ],

          // ---- Subject + salutation --------------------------------------
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
          ),
          pw.SizedBox(height: 12),
          if (!_startsWithSalutation(body)) ...<pw.Widget>[
            pw.Text(
              recipient == null
                  ? 'Dear colleague,'
                  : _latin1Safe(recipient.salutation),
              style: base,
            ),
            pw.SizedBox(height: 10),
          ],

          // ---- Body ------------------------------------------------------
          ..._markdownBlocks(body, base),

          // ---- Sign-off --------------------------------------------------
          pw.SizedBox(height: 22),
          pw.Text('Yours sincerely,', style: base),
          pw.SizedBox(height: 30),
          pw.Container(
            width: 180,
            padding: const pw.EdgeInsets.only(top: 3),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.7)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(clinicianName,
                    style: pw.TextStyle(
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold,
                    )),
                if (clinicName != null) pw.Text(clinicName, style: mutedSmall),
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// A model told to write a letter often opens with its own greeting; adding
  /// a second reads as a template accident.
  static bool _startsWithSalutation(String body) {
    final first = body.trimLeft().toLowerCase();
    return first.startsWith('dear ') || first.startsWith('to whom');
  }

  // ---- Markdown → pdf widgets -------------------------------------------

  /// Block-level rendering: headings, bullet and numbered lists, paragraphs.
  static List<pw.Widget> _markdownBlocks(String body, pw.TextStyle base) {
    final blocks = <pw.Widget>[];

    for (final rawLine in body.trim().split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        blocks.add(pw.SizedBox(height: 6));
        continue;
      }

      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line.trim());
      if (heading != null) {
        blocks.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
          child: pw.Text(
            heading.group(2)!,
            style: base.copyWith(
              fontSize: heading.group(1)!.length == 1 ? 12.5 : 11.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ));
        continue;
      }

      final bullet = RegExp(r'^[-*•]\s+(.*)$').firstMatch(line.trim());
      final numbered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(line.trim());
      if (bullet != null || numbered != null) {
        final marker = bullet != null ? '•' : '${numbered!.group(1)}.';
        final text = bullet?.group(1) ?? numbered!.group(2)!;
        blocks.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 14, bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.SizedBox(
                width: 18,
                child: pw.Text(marker, style: base),
              ),
              pw.Expanded(child: _inline(text, base)),
            ],
          ),
        ));
        continue;
      }

      blocks.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: _inline(line.trim(), base),
      ));
    }

    return blocks;
  }

  /// Inline **bold** and *italic* within a line.
  static pw.Widget _inline(String text, pw.TextStyle base) {
    final spans = <pw.InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|__(.+?)__|_(.+?)_');
    var cursor = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
            pw.TextSpan(text: text.substring(cursor, match.start), style: base));
      }
      final bold = match.group(1) ?? match.group(3);
      final italic = match.group(2) ?? match.group(4);
      spans.add(pw.TextSpan(
        text: bold ?? italic!,
        style: base.copyWith(
          fontWeight: bold != null ? pw.FontWeight.bold : null,
          fontStyle: italic != null ? pw.FontStyle.italic : null,
        ),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(pw.TextSpan(text: text.substring(cursor), style: base));
    }

    return pw.RichText(text: pw.TextSpan(children: spans, style: base));
  }
}
