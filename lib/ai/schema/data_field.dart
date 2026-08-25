import '../../core/utils/formatters.dart';

/// What kind of thing a column holds, in the sense that decides what can be
/// done with it.
///
/// Not the SQL type. `news2_score` and `pain_score` are both `INTEGER`, and so
/// is `on_oxygen`; averaging the first two is meaningful and averaging the
/// third is nonsense. The distinction that matters for analysis is whether a
/// value can be added up, grouped by, placed on a timeline, or only read.
enum FieldKind {
  /// Can be averaged, summed, correlated, binned.
  numeric,

  /// A small set of repeated values. Groups into bars or slices.
  categorical,

  /// An instant. Becomes an axis, and buckets into days, weeks or months.
  temporal,

  /// Prose. Searchable, never plottable.
  text,

  /// Yes or no. Groups like a category, never averaged.
  boolean,

  /// Names a person or a record — a phone number, an MRN, an email.
  ///
  /// Its own kind because it fails *both* of the useful tests: it is not
  /// prose (searching a phone number for words is meaningless) and it is not
  /// a category (a chart grouped by phone number is one bar per patient).
  /// What it can do is be shown — it exists for projection, "patients and
  /// their contact numbers", where the answer is a column in a table.
  identifier,
}

/// One column, described so a question can find it.
///
/// [synonyms] is the part that earns its keep. People do not say
/// `systolic_bp`; they say blood pressure, BP, systolic, or top number. A
/// registry that only knows column names answers almost nothing, and one that
/// guesses from spelling alone matches "site" to "sites" and "spo2" to "sp".
/// Named synonyms first, fuzzy matching only as a fallback.
class DataField {
  const DataField({
    required this.name,
    required this.label,
    required this.kind,
    this.synonyms = const <String>[],
    this.sources = const <String>[],
    this.unit,
    this.derive,
    this.valueLabels,
    this.higherIsBetter,
    this.screenHigh,
    this.screenLow,
  });

  /// Stable identifier, used in explanations and tests.
  final String name;

  /// How it reads on an axis.
  final String label;

  final FieldKind kind;

  final List<String> synonyms;

  /// The SQL columns this needs. Empty means [name] is the column.
  ///
  /// Everything that reaches SQL comes from here, never from what was typed.
  /// A question chooses *which registry entry* to use; it never contributes an
  /// identifier. That is the property that keeps a text-to-analysis feature
  /// from being a text-to-SQL feature.
  final List<String> sources;

  final String? unit;

  /// Computes the value from the row when it is not simply a column — age from
  /// a date of birth, a visit's length from its two timestamps.
  final Object? Function(Map<String, Object?> row)? derive;

  /// Prettier names for stored codes: `followUp` → `Follow-up`.
  final Map<String, String>? valueLabels;

  /// For a numeric field where direction has clinical meaning, so a trend can
  /// be described as improving rather than merely rising. Null where rising is
  /// neither good nor bad.
  final bool? higherIsBetter;

  /// Screening thresholds, for reading "high X" and "low X".
  ///
  /// "Patients with high BP" has to mean *something specific*, and the honest
  /// options are to refuse the word or to publish the number. These are the
  /// published numbers: values at or above [screenHigh] (or at or below
  /// [screenLow]) are what the qualifier selects, they mirror the NEWS2 and
  /// NICE screening cut-offs the rest of the app already uses, and every
  /// answer states the threshold it applied.
  ///
  /// They are *screening* bounds, not diagnoses — one reading of 142 mmHg is
  /// a reading, not hypertension — and the wording downstream keeps that
  /// distinction. Null on both means the qualifier is refused for this field.
  final double? screenHigh;
  final double? screenLow;

  List<String> get columns => sources.isEmpty ? <String>[name] : sources;

  /// Reads this field out of a row whose columns were selected with [prefix].
  Object? read(Map<String, Object?> row, {String prefix = ''}) {
    if (derive != null) {
      return derive!(<String, Object?>{
        for (final column in columns) column: row['$prefix$column'],
      });
    }
    return row['$prefix${columns.first}'];
  }

  /// The value as a number, or null when it is missing or unusable.
  double? numberIn(Map<String, Object?> row, {String prefix = ''}) {
    final value = read(row, prefix: prefix);
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// The value as a group label, or null when it is missing.
  ///
  /// Missing is deliberately *not* rendered as "Unknown" here. A bucket
  /// labelled Unknown sits in a chart looking like a finding; a row that was
  /// never recorded is an absence, and the caller decides whether to say so.
  String? labelIn(Map<String, Object?> row, {String prefix = ''}) {
    final value = read(row, prefix: prefix);
    if (value == null) return null;
    if (kind == FieldKind.boolean) {
      final truthy = value == 1 || value == true || value == '1';
      return truthy ? 'Yes' : 'No';
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    return valueLabels?[raw] ?? Fmt.sentence(raw);
  }

  /// The value as it should be shown to a person, kind-aware.
  ///
  /// One implementation because it was about to be three: the projection
  /// table, the ranked list and the capability sheet all need "this cell,
  /// readable", and three copies of date-vs-code-vs-number logic is how the
  /// same value ends up formatted differently on one screen.
  String display(Map<String, Object?> row, {String prefix = ''}) {
    final value = read(row, prefix: prefix);
    if (value == null) return '—';
    switch (kind) {
      case FieldKind.numeric:
        final number = numberIn(row, prefix: prefix);
        return number == null ? '—' : Fmt.stat(number, unit: unit);
      case FieldKind.temporal:
        final instant = switch (value) {
          final int epoch => DateTime.fromMillisecondsSinceEpoch(epoch),
          final String iso => DateTime.tryParse(iso),
          _ => null,
        };
        return instant == null ? '—' : Fmt.date(instant);
      case FieldKind.categorical || FieldKind.boolean:
        return labelIn(row, prefix: prefix) ?? '—';
      case FieldKind.identifier || FieldKind.text:
        final raw = value.toString().trim();
        return raw.isEmpty ? '—' : raw;
    }
  }
}

/// One table, described the way someone would ask about it.
class DataTable {
  const DataTable({
    required this.name,
    required this.label,
    required this.singular,
    required this.fields,
    this.synonyms = const <String>[],
    this.timeField,
    this.patientColumn,
    this.softDeleted = true,
  });

  /// The SQL table name.
  final String name;

  /// Plural, for headlines: "visits".
  final String label;
  final String singular;

  final List<String> synonyms;
  final List<DataField> fields;

  /// The column a question about *when* means by default.
  final String? timeField;

  /// How rows here reach a patient, for joining patient attributes on. Null on
  /// `patients` itself and on tables with no patient.
  final String? patientColumn;

  final bool softDeleted;

  DataField? field(String name) {
    for (final candidate in fields) {
      if (candidate.name == name) return candidate;
    }
    return null;
  }

  DataField? get defaultTime => timeField == null ? null : field(timeField!);

  Iterable<DataField> ofKind(FieldKind kind) =>
      fields.where((f) => f.kind == kind);
}

/// A field found by name, and the table it belongs to.
typedef FieldMatch = ({DataTable table, DataField field, double confidence});
