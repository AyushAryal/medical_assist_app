import '../analytics/period_parser.dart';
import '../schema/field_registry.dart';
import 'rank_spec.dart';

/// Reads "who stands out" questions into a [RankSpec].
///
/// Three grammars, one intent:
///
/// ```
///   superlative:   riskiest patients · oldest patients · top 10 by bmi
///   qualifier:     patients with high bp · low sats · fever
///   threshold:     news2 above 5 · temperature over 38
/// ```
///
/// The qualifier grammar is the one that earns the file. "High" has to mean
/// something specific, and the honest options are to refuse the word or to
/// publish the number — so each measure carries its screening cut-off in the
/// registry ([DataField.screenHigh]/[screenLow]), the parser only accepts the
/// word where a cut-off exists, and the answer states the number it used.
///
/// A bare superlative with no person in the sentence — "highest BMI" — is
/// declined and left to the analysis parser, whose maximum-of-a-column is the
/// right answer to it. "Patients with the highest BMI" is this parser's,
/// because the question is *who*.
abstract final class RankParser {
  /// Words that make the question about people rather than about a value.
  static final RegExp _personWords =
      RegExp(r'\b(?:patients?|people|person|who|anyone|kids|children|adults)\b');

  static final RegExp _descending = RegExp(
      r'\b(?:highest|riskiest|sickest|most at risk|most unwell|worst|top|'
      r'largest|biggest|greatest|heaviest|oldest|eldest)\b');
  static final RegExp _ascending =
      RegExp(r'\b(?:lowest|bottom|smallest|least|lightest|youngest)\b');

  /// Superlatives that *are* the measure. "Riskiest" says both "order
  /// descending" and "by NEWS2"; nobody says "riskiest by NEWS2".
  static const Map<String, (String field, bool descending)> _impliedMeasure =
      <String, (String, bool)>{
    'riskiest': ('news2_score', true),
    'sickest': ('news2_score', true),
    'most at risk': ('news2_score', true),
    'most unwell': ('news2_score', true),
    'deteriorating': ('news2_score', true),
    'oldest': ('age', true),
    'eldest': ('age', true),
    'youngest': ('age', false),
    'heaviest': ('weight_kg', true),
    'lightest': ('weight_kg', false),
  };

  /// Clinical words that carry both the measure and the direction.
  ///
  /// Deliberately not including diagnosis words like "hypertensive" or
  /// "diabetic" — those belong to the problem-list cohort matcher, and the
  /// difference matters: "hypertensive patients" is the diagnosed; "patients
  /// with high BP" is the measured, and the two lists disagree in exactly the
  /// ways a clinician needs to see.
  static const Map<String, (String field, bool high)> _conditionWords =
      <String, (String, bool)>{
    'fever': ('temperature_c', true),
    'febrile': ('temperature_c', true),
    'pyrexial': ('temperature_c', true),
    'hypoxic': ('spo2', false),
    'desaturating': ('spo2', false),
    'tachycardic': ('heart_rate', true),
    'bradycardic': ('heart_rate', false),
    'hypotensive': ('systolic_bp', false),
    'hyperglycaemic': ('blood_glucose_mmol', true),
    'hypoglycaemic': ('blood_glucose_mmol', false),
  };

  static RankSpec? parse(String question, {DateTime? asOf}) {
    var text = question.toLowerCase().trim();
    if (text.isEmpty) return null;
    final now = asOf ?? DateTime.now();

    final period = PeriodParser.take(text, now);
    text = period.rest;

    // "top 10", "10 riskiest", "5 highest".
    var limit = 10;
    final counted = RegExp(r'\b(?:top|first)\s+(\d{1,3})\b').firstMatch(text) ??
        RegExp(r'\b(\d{1,3})\s+(?=(?:highest|lowest|riskiest|sickest|oldest|'
                r'youngest|heaviest|lightest|top|worst)\b)')
            .firstMatch(text);
    var explicitCount = false;
    // "Top" is both the count marker and a direction: "top 5 by BMI" means
    // highest first even though no superlative survives the cut below.
    var impliedDescending = false;
    if (counted != null) {
      limit = int.parse(counted.group(1)!).clamp(1, 100);
      explicitCount = true;
      impliedDescending = RegExp(r'\btop\b').hasMatch(text);
      text = _cut(text, counted.start, counted.end);
    }
    if (RegExp(r'\btop\b').hasMatch(text)) {
      impliedDescending = true;
      text = text.replaceAll(RegExp(r'\btop\b'), ' ');
    }

    final hasPerson = _personWords.hasMatch(text);

    // Condition words first: they are the most specific claim.
    for (final entry in _conditionWords.entries) {
      if (RegExp('\\b${entry.key}\\b').hasMatch(text)) {
        final field = _vital(entry.value.$1);
        final high = entry.value.$2;
        final cutoff = high ? field.field.screenHigh : field.field.screenLow;
        if (cutoff == null) return null;
        return RankSpec(
          table: field.table,
          measure: field.field,
          descending: high,
          limit: explicitCount ? limit : 25,
          cutoff: cutoff,
          qualifier: entry.key,
          periodFrom: period.from,
          periodTo: period.to,
        );
      }
    }

    // Explicit threshold: "<field> above 5", "<field> over 38".
    final threshold = RegExp(
      r'^(.*?)\s+(above|over|at least|greater than|below|under|less than|'
      r'at most)\s+(\d+(?:\.\d+)?)\b(.*)$',
    ).firstMatch(text);
    if (threshold != null) {
      final phrase = _tidy('${threshold.group(1)!} ${threshold.group(4)!}');
      final match = _numericField(phrase);
      if (match != null) {
        final upward = !RegExp(r'below|under|less than|at most')
            .hasMatch(threshold.group(2)!);
        return RankSpec(
          table: match.table,
          measure: match.field,
          descending: upward,
          limit: explicitCount ? limit : 25,
          cutoff: double.parse(threshold.group(3)!),
          periodFrom: period.from,
          periodTo: period.to,
        );
      }
    }

    // Qualifier: "high bp", "raised temperature", "low sats".
    final qualified = RegExp(
      r'\b(high|raised|elevated|low)\s+((?:\w+\s?){1,4})',
    ).firstMatch(text);
    if (qualified != null) {
      final word = qualified.group(1)!;
      final match = _numericField(_tidy(qualified.group(2)!));
      if (match != null) {
        final high = word != 'low';
        final cutoff =
            high ? match.field.screenHigh : match.field.screenLow;
        // No published cut-off means the word is refused rather than guessed —
        // "high occupation" and "high age" have no honest number.
        if (cutoff != null) {
          return RankSpec(
            table: match.table,
            measure: match.field,
            descending: high,
            limit: explicitCount ? limit : 25,
            cutoff: cutoff,
            qualifier: '$word ${_tidy(qualified.group(2)!)}',
            periodFrom: period.from,
            periodTo: period.to,
          );
        }
      }
    }

    // Implied-measure superlatives: "riskiest patients".
    for (final entry in _impliedMeasure.entries) {
      if (!RegExp('\\b${entry.key}\\b').hasMatch(text)) continue;
      if (!hasPerson && !explicitCount) return null;
      final match = _numericField(entry.value.$1);
      if (match == null) return null;
      return RankSpec(
        table: match.table,
        measure: match.field,
        descending: entry.value.$2,
        limit: limit,
        periodFrom: period.from,
        periodTo: period.to,
      );
    }

    // Bare-direction superlatives: "patients with the highest bmi",
    // "top 5 by waiting time".
    final directed = _descending.hasMatch(text)
        ? true
        : _ascending.hasMatch(text)
            ? false
            : impliedDescending
                ? true
                : null;
    if (directed == null) return null;
    // Without a person or a count this is "highest bmi" — a maximum, which is
    // the analysis parser's answer, not a ranking.
    if (!hasPerson && !explicitCount) return null;

    var phrase = text
        .replaceAll(_descending, ' ')
        .replaceAll(_ascending, ' ')
        .replaceAll(_personWords, ' ');
    phrase = _tidy(phrase);
    if (phrase.isEmpty) return null;

    final match = _numericField(phrase);
    if (match == null) return null;

    return RankSpec(
      table: match.table,
      measure: match.field,
      descending: directed,
      limit: limit,
      periodFrom: period.from,
      periodTo: period.to,
    );
  }

  static FieldMatch _vital(String name) {
    final table = name == 'age' ? FieldRegistry.patients : FieldRegistry.vitals;
    return (table: table, field: table.field(name)!, confidence: 1);
  }

  static FieldMatch? _numericField(String phrase) {
    if (phrase.isEmpty) return null;
    final match = FieldRegistry.resolveField(phrase);
    if (match == null || match.field.kind != FieldKind.numeric) return null;
    return match;
  }

  static String _cut(String text, int start, int end) =>
      _tidy(text.replaceRange(start, end, ' '));

  static String _tidy(String value) => value
      .replaceAll(
        RegExp(r'\b(?:the|a|an|of|in|for|with|by|their|our|my|all|and|'
            r'recorded|reading|readings|value|values|first|ranked|rank|'
            r'order|ordered|sort|sorted)\b'),
        ' ',
      )
      .replaceAll(RegExp(r'[?!.,;:]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
