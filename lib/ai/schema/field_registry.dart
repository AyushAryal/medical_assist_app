import '../../core/utils/text_similarity.dart';
import 'clinical_tables.dart';
import 'data_field.dart';

// One import serves the whole module: everything that resolves fields also
// consumes the types and, usually, a table or two by name.
export 'clinical_tables.dart';
export 'data_field.dart';

/// Everything this app can analyse, and the words that reach it.
///
/// The whole point of writing the schema down twice — once as DDL, once here
/// with meanings — is that the second copy is what makes a question answerable
/// without generating SQL. A request picks a table and one or two fields *from
/// this list*; the query is then assembled from registry identifiers only.
///
/// It also means the app can say what it knows. A search that cannot enumerate
/// its own vocabulary leaves people guessing at magic words.
abstract final class FieldRegistry {
  // The vocabulary itself lives in `clinical_tables.dart`; these aliases keep
  // every call site addressing one name for both the data and the matching.
  static final DataTable patients = ClinicalTables.patients;
  static final DataTable encounters = ClinicalTables.encounters;
  static final DataTable appointments = ClinicalTables.appointments;
  static final DataTable vitals = ClinicalTables.vitals;
  static final DataTable notes = ClinicalTables.notes;
  static final DataTable medications = ClinicalTables.medications;
  static final DataTable problems = ClinicalTables.problems;
  static final DataTable allergies = ClinicalTables.allergies;
  static final DataTable attachments = ClinicalTables.attachments;

  /// Below this, a fuzzy match is a coincidence rather than a synonym.
  ///
  /// Set high on purpose. Charting the wrong column is worse than saying "I do
  /// not know that field": a wrong chart is confidently wrong and nothing on
  /// screen contradicts it.
  static const double _fuzzyFloor = 0.90;

  /// Every analysable table, in the order they are offered.
  static final List<DataTable> tables = <DataTable>[
    patients,
    encounters,
    appointments,
    vitals,
    notes,
    medications,
    problems,
    allergies,
    attachments,
  ];

  static DataTable? byName(String name) {
    for (final table in tables) {
      if (table.name == name) return table;
    }
    return null;
  }

  /// Finds the table a phrase is about.
  static ({DataTable table, double confidence})? resolveTable(String phrase) {
    final term = _normalise(phrase);
    if (term.isEmpty) return null;

    for (final table in tables) {
      for (final word in <String>[table.name, table.label, table.singular,
          ...table.synonyms]) {
        if (_normalise(word) == term) {
          return (table: table, confidence: 1);
        }
      }
    }

    ({DataTable table, double confidence})? best;
    for (final table in tables) {
      for (final word in <String>[table.label, table.singular,
          ...table.synonyms]) {
        final score = TextSimilarity.jaroWinkler(term, _normalise(word));
        if (score >= _fuzzyFloor &&
            (best == null || score > best.confidence)) {
          best = (table: table, confidence: score);
        }
      }
    }
    return best;
  }

  /// Finds the field a phrase is about, optionally preferring one table.
  ///
  /// Searching across every table is what makes "average blood pressure by
  /// city" work without being told that pressure lives on observations and
  /// city on patients. [within] only breaks ties — it never hides a field that
  /// is a better match elsewhere, because a question that names a field the
  /// current table does not have is usually a question about the other table.
  static FieldMatch? resolveField(String phrase, {DataTable? within}) {
    final term = _normalise(phrase);
    if (term.isEmpty) return null;

    FieldMatch? best;
    void consider(DataTable table, DataField field, double score) {
      if (score < _fuzzyFloor) return;
      final adjusted = identical(table, within) ? score + 0.02 : score;
      if (best == null || adjusted > best!.confidence) {
        best = (table: table, field: field, confidence: adjusted.clamp(0, 1));
      }
    }

    for (final table in tables) {
      for (final field in table.fields) {
        for (final word in <String>[field.name, field.label,
            ...field.synonyms]) {
          final normalised = _normalise(word);
          if (normalised == term) {
            consider(table, field, 1);
          } else {
            consider(table, field, TextSimilarity.jaroWinkler(term, normalised));
          }
        }
      }
    }
    return best;
  }

  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
