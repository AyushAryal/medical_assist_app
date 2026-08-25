import '../../core/utils/formatters.dart';
import '../schema/field_registry.dart';
import 'analysis.dart';

/// One suggested question, with what it will produce.
typedef AnalysisExample = ({String question, String shows, ChartStyle style});

/// A group of suggestions for one table.
typedef ExampleGroup = ({
  String title,
  String subtitle,
  List<AnalysisExample> examples,
});

/// Chartable questions, generated from the registry rather than written out.
///
/// The reason to generate them is that a hand-written list of examples drifts:
/// a field gets renamed, a synonym changes, and the app is left advertising a
/// question it no longer understands — which is worse than advertising nothing,
/// because the first thing someone does with the feature is watch a suggestion
/// the app made itself come back empty.
///
/// Because these are built from the same [FieldRegistry] entries the parser
/// resolves against, a suggestion can only exist if the field behind it does.
/// A test walks every one of them through the parser to close the loop.
abstract final class AnalysisExamples {
  /// Tables worth suggesting, in the order a clinician would care.
  static List<ExampleGroup> get groups => <ExampleGroup>[
        for (final table in <DataTable>[
          FieldRegistry.vitals,
          FieldRegistry.encounters,
          FieldRegistry.appointments,
          FieldRegistry.patients,
          FieldRegistry.medications,
          FieldRegistry.problems,
          FieldRegistry.notes,
        ])
          (
            title: _titleCase(table.label),
            subtitle: _subtitleFor(table),
            examples: _forTable(table),
          ),
      ];

  /// Everything, flattened — for the test that holds this honest.
  static List<AnalysisExample> get all => <AnalysisExample>[
        for (final group in groups) ...group.examples,
      ];

  static List<AnalysisExample> _forTable(DataTable table) {
    final numeric = table.ofKind(FieldKind.numeric).toList();
    final categorical = <DataField>[
      ...table.ofKind(FieldKind.categorical),
      ...table.ofKind(FieldKind.boolean),
    ];
    final out = <AnalysisExample>[];

    // How much of something there is over time — the question every clinic
    // manager asks first.
    if (table.defaultTime != null) {
      out.add((
        question: '${table.label} per month',
        shows: 'How the volume of ${table.label} has moved',
        style: ChartStyle.area,
      ));
    }

    // The typical value of a measurement, cut by something about the person or
    // the visit. This is the shape most clinical audit questions take.
    if (numeric.isNotEmpty && categorical.isNotEmpty) {
      out.add((
        question: 'average ${_word(numeric.first)} by ${_word(categorical.first)}',
        shows: 'Whether ${_word(numeric.first)} differs by '
            '${_word(categorical.first)}',
        style: ChartStyle.bar,
      ));
    }

    // A share of the whole reads best as a ring, and only counts can be one.
    if (categorical.isNotEmpty) {
      out.add((
        question: '${table.label} by ${_word(categorical.first)} as a pie chart',
        shows: 'The split of ${table.label} across '
            '${_word(categorical.first)}',
        style: ChartStyle.pie,
      ));
    }

    // The spread, which is what a mean hides.
    if (numeric.isNotEmpty) {
      out.add((
        question: 'distribution of ${_word(numeric.first)}',
        shows: 'The spread of ${_word(numeric.first)}, not just its average',
        style: ChartStyle.histogram,
      ));
    }

    // Whether two measurements move together. Only offered where the table
    // genuinely holds two, so there is something to plot against something.
    if (numeric.length >= 2) {
      out.add((
        question: '${_word(numeric[0])} against ${_word(numeric[1])}',
        shows: 'Whether ${_word(numeric[0])} and ${_word(numeric[1])} move '
            'together',
        style: ChartStyle.scatter,
      ));
    }

    // Grouping by a patient attribute, which is the join the registry exists
    // to make possible from a phrase.
    if (table.patientColumn != null && numeric.isNotEmpty) {
      out.add((
        question: 'average ${_word(numeric.first)} by district',
        shows: 'Whether ${_word(numeric.first)} varies by where people live',
        style: ChartStyle.bar,
      ));
    }

    return out;
  }

  /// The first synonym, which is the phrasing a person would actually say —
  /// the label is title-cased for an axis and reads oddly mid-sentence.
  static String _word(DataField field) => field.synonyms.isEmpty
      ? field.label.toLowerCase()
      : field.synonyms.first;

  static String _subtitleFor(DataTable table) {
    final numeric = table.ofKind(FieldKind.numeric).length;
    final categorical = table.ofKind(FieldKind.categorical).length;
    return '$numeric measurable, $categorical groupable';
  }

  static String _titleCase(String value) => Fmt.titleCase(value);
}
