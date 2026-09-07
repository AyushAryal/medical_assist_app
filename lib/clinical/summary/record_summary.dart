import '../flags/clinical_flag.dart';

/// Whether a fact is on the record, or simply absent.
///
/// The distinction is the whole point of this engine. A blank allergy field
/// and "no known allergies" look the same on screen and mean opposite things;
/// collapsing them is how an allergy gets missed. So absence is a *value*,
/// [SummaryState.notRecorded], rendered as "Not recorded" — never a blank,
/// never a reassuring default.
enum SummaryState { recorded, notRecorded }

/// One line of a prime-the-chart pre-read.
class SummaryItem {
  const SummaryItem({
    required this.label,
    required this.value,
    required this.state,
    required this.source,
    this.severity,
  });

  final String label;

  /// The rendered value — a joined list, a score, or "Not recorded".
  final String value;
  final SummaryState state;

  /// Where this line was read from, for an InfoDot. Every derived line is
  /// auditable.
  final String source;

  /// A clinical tone when the line itself carries risk (allergies present, an
  /// unknown allergy status, an elevated score). Null when it is neutral.
  final FlagSeverity? severity;

  bool get isRecorded => state == SummaryState.recorded;
}

class SummarySection {
  const SummarySection({
    required this.key,
    required this.title,
    required this.items,
  });

  final String key;
  final String title;
  final List<SummaryItem> items;
}

/// A deterministic, sourced view of a patient's record.
///
/// Built by [SummaryBuilder] from a snapshot; the same snapshot always yields
/// the same summary. Prime-the-chart uses the whole thing; a handoff later
/// selects a subset — same builder, same guarantees.
class RecordSummary {
  const RecordSummary({
    required this.patientId,
    required this.asOf,
    required this.sections,
  });

  final String patientId;
  final DateTime asOf;
  final List<SummarySection> sections;

  Iterable<SummaryItem> get allItems => sections.expand((s) => s.items);

  /// A flat, deterministic text rendering — one `label: value` per line. Used
  /// as the input a model rewrites into a spoken brief, so the model only ever
  /// sees the summary the app already built, never the raw record.
  String get plainText {
    final buffer = StringBuffer();
    for (final item in allItems) {
      buffer.writeln('${item.label}: ${item.value}');
    }
    return buffer.toString().trimRight();
  }

  /// The gaps — every required line the record does not yet hold. Lets a
  /// screen show "3 things not recorded" instead of the reader having to
  /// notice each absence.
  List<SummaryItem> get notRecorded =>
      allItems.where((i) => !i.isRecorded).toList(growable: false);
}
