import '../cohort/cohort_query.dart';
import '../schema/field_registry.dart';

/// One "who stands out" question, fully specified.
///
/// The third question shape, after cohorts ("who matches these filters") and
/// analyses ("what is the aggregate shape"). "Riskiest patients", "patients
/// with high BP" and "top ten by BMI" are all this one: *pick people by a
/// measured value* — ordered by it, optionally cut off at a threshold, capped
/// at a count.
///
/// Like an [AnalysisSpec], everything here is a registry object. A question
/// selects the measure from [FieldRegistry]; no identifier a person typed
/// ever reaches a statement.
class RankSpec {
  const RankSpec({
    required this.table,
    required this.measure,
    required this.descending,
    this.limit = 10,
    this.cutoff,
    this.qualifier,
    this.periodFrom,
    this.periodTo,
    this.sexAtBirth,
    this.ageBand,
  });

  /// Where the measured value lives. `patients` for age; `vitals` for a
  /// reading, in which case rows are folded to one extreme per patient.
  final DataTable table;

  final DataField measure;

  /// True for "highest first". Which end is *worst* is the measure's own
  /// knowledge ([DataField.higherIsBetter]), not this spec's.
  final bool descending;

  /// How many people to show. The qualifying *count* is always reported in
  /// full — the limit caps the list, never the number.
  final int limit;

  /// Keep only values at-or-beyond this, on the sorted end: at-or-above when
  /// [descending], at-or-below otherwise. Null ranks everyone with a value.
  final double? cutoff;

  /// The word that produced [cutoff] — "high", "fever" — kept so the answer
  /// can show its reading of the word next to the number it chose for it.
  final String? qualifier;

  final DateTime? periodFrom;
  final DateTime? periodTo;

  /// Demographic narrowing, set by conversation — "riskiest patients" then
  /// "only the women". Applied to the *patients*, not to the readings: a
  /// woman's ranking uses all her observations, not just some of them.
  final String? sexAtBirth;
  final AgeBand? ageBand;

  RankSpec copyWith({
    int? limit,
    double? cutoff,
    bool clearCutoff = false,
    String? qualifier,
    DateTime? periodFrom,
    DateTime? periodTo,
    String? sexAtBirth,
    AgeBand? ageBand,
    DataField? measure,
    DataTable? table,
    bool? descending,
  }) =>
      RankSpec(
        table: table ?? this.table,
        measure: measure ?? this.measure,
        descending: descending ?? this.descending,
        limit: limit ?? this.limit,
        cutoff: clearCutoff ? null : (cutoff ?? this.cutoff),
        qualifier: clearCutoff ? null : (qualifier ?? this.qualifier),
        periodFrom: periodFrom ?? this.periodFrom,
        periodTo: periodTo ?? this.periodTo,
        sexAtBirth: sexAtBirth ?? this.sexAtBirth,
        ageBand: ageBand ?? this.ageBand,
      );

  /// How this reads back, threshold included. "High BP" answered without
  /// stating the 140 it was taken to mean is a guess wearing a lab coat.
  String describe() {
    final unit = measure.unit == null ? '' : ' ${measure.unit}';
    final bound = cutoff == null
        ? (descending ? 'highest first' : 'lowest first')
        : descending
            ? '${_trim(cutoff!)}$unit or more'
            : '${_trim(cutoff!)}$unit or less';
    final read = qualifier == null ? '' : '"$qualifier" read as ';
    final who = <String>[
      if (sexAtBirth != null) '$sexAtBirth only',
      if (ageBand != null) 'aged ${ageBand!.label.toLowerCase()}',
    ];
    return 'by ${measure.label.toLowerCase()} — $read$bound'
        '${who.isEmpty ? '' : ' · ${who.join(' · ')}'}';
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();
}
