import '../../core/utils/formatters.dart';
import '../cohort/cohort_query.dart';
import '../../data/dao/analysis_dao.dart';
import '../../data/dao/cohort_dao.dart';
import '../../data/repositories/clinical_repository.dart';
import '../analytics/analysis.dart';
import '../../clinical/explanations.dart';
import '../intent.dart';
import '../presentation.dart';
import '../provenance.dart';
import '../records/rank_spec.dart';
import '../schema/field_registry.dart';

/// Answers "who stands out": ranks people by a measured value.
///
/// The folding rule is the clinically load-bearing part. A patient with five
/// observations is five rows, and ranking rows would put one deteriorating
/// patient in half the list while a patient measured once sits invisibly
/// below them. So rows fold to **one extreme per patient** — the highest
/// reading when ranking downward, the lowest when ranking upward — and the
/// answer says which reading it kept and when it was taken.
///
/// The other rule is the wording. A ranking by measured values must never
/// read as diagnosis: "patients with high BP" answered from `vitals` is the
/// *measured*, not the *diagnosed*, and the two lists disagree in exactly the
/// ways a clinician needs to see. Every headline and explanation here keeps
/// that distinction explicit.
class RankHandler {
  const RankHandler(this._repository, this._dao);

  final ClinicalRepository _repository;
  final AnalysisDao _dao;

  Future<Presentation> run(RankIntent intent, Provenance provenance) async {
    final spec = intent.spec;
    final onPatients = spec.table.name == FieldRegistry.patients.name;

    // Demographic narrowing needs the patient's sex and age beside every
    // reading, so they ride along in the same read rather than costing a
    // second query per patient.
    final needsDemographics = spec.sexAtBirth != null || spec.ageBand != null;
    final sexField = FieldRegistry.patients.field('sex_at_birth')!;
    final ageField = FieldRegistry.patients.field('age')!;

    final data = await _dao.read(AnalysisSpec(
      table: spec.table,
      aggregate: spec.descending ? Aggregate.max : Aggregate.min,
      measure: spec.measure,
      periodFrom: spec.periodFrom,
      periodTo: spec.periodTo,
      patientFields: needsDemographics
          ? <DataField>[sexField, ageField]
          : const <DataField>[],
    ));

    // Which prefix the demographics arrived under: on the patients table they
    // are the subject's own columns; everywhere else they came through the
    // join.
    final demographicPrefix = onPatients
        ? AnalysisDao.subjectPrefix
        : AnalysisDao.patientPrefix;

    bool demographicsMatch(Map<String, Object?> row) {
      if (!needsDemographics) return true;
      if (spec.sexAtBirth case final sex?) {
        final recorded = row['$demographicPrefix${sexField.columns.first}'];
        if (recorded is! String || recorded.toLowerCase() != sex) return false;
      }
      if (spec.ageBand case final band?) {
        final age = ageField.numberIn(row, prefix: demographicPrefix);
        // No date of birth means no age band — excluded rather than guessed,
        // and the explanation says how many that dropped.
        if (age == null) return false;
        if (age < band.minYears) return false;
        if (band.maxYears case final max? when age >= max) return false;
      }
      return true;
    }

    // One extreme per patient, with when it was recorded.
    final best = <String, ({double value, DateTime? at})>{};
    var unattributed = 0;
    final prefix = AnalysisDao.subjectPrefix;
    final time = spec.table.defaultTime;

    for (final row in data.rows) {
      if (!demographicsMatch(row)) continue;
      final value = spec.measure.numberIn(row, prefix: prefix);
      if (value == null) continue;
      if (spec.cutoff case final cutoff?) {
        if (spec.descending ? value < cutoff : value > cutoff) continue;
      }
      final key = onPatients
          ? row['${prefix}id'] as String?
          : row['$prefix${spec.table.patientColumn}'] as String?;
      if (key == null) {
        unattributed++;
        continue;
      }
      final held = best[key];
      final better = held == null ||
          (spec.descending ? value > held.value : value < held.value);
      if (better) {
        best[key] = (value: value, at: _instant(time?.read(row, prefix: prefix)));
      }
    }

    provenance.add(
      'execute',
      'Measured ${best.length} '
          '${best.length == 1 ? 'patient' : 'patients'} '
          'from ${data.rows.length} recorded values',
      detail: onPatients
          ? null
          : 'Each patient counts once, by their single '
              '${spec.descending ? 'highest' : 'lowest'} recorded value.',
    );

    if (best.isEmpty) {
      return MessagePresentation(
        headline: spec.cutoff == null
            ? 'Nothing recorded for '
                '${spec.measure.label.toLowerCase()} yet.'
            : 'No one has a recorded ${spec.measure.label.toLowerCase()} '
                '${spec.describe().split('— ').last}.',
        suggestions: <String>[
          'distribution of ${spec.measure.label.toLowerCase()}',
          '${spec.table.label} per month',
        ],
      );
    }

    final ordered = best.entries.toList()
      ..sort((a, b) => spec.descending
          ? b.value.value.compareTo(a.value.value)
          : a.value.value.compareTo(b.value.value));
    final top = ordered.take(spec.limit).toList();

    // Small and bounded — the limit caps this at a couple of dozen lookups,
    // and each returns a full Patient so the rows are the same tappable
    // people every other list in the app shows.
    final rows = <CohortRow>[];
    final cells = <List<String>>[];
    for (final entry in top) {
      final patient = await _repository.patients.byId(entry.key);
      if (patient == null) continue;
      final value = Fmt.stat(entry.value.value, unit: spec.measure.unit);
      rows.add((
        patient: patient,
        detail: '${spec.measure.label} $value'
            '${entry.value.at == null ? '' : ' · ${Fmt.dateShort(entry.value.at)}'}',
        lastSeen: patient.lastSeenAt,
      ));
      cells.add(<String>[
        value,
        entry.value.at == null ? '—' : Fmt.date(entry.value.at),
      ]);
    }

    return MetricPresentation(
      value: best.length,
      label: 'patient',
      headline: _headline(spec, best.length),
      rows: rows,
      total: best.length,
      columns: <String>[spec.measure.label, 'Recorded'],
      cells: cells,
      explanation: _explain(
        spec,
        qualifying: best.length,
        readingsSeen: data.rows.length,
        unattributed: unattributed,
        shown: rows.length,
      ),
    );
  }

  static MetricExplanation _explain(
    RankSpec spec, {
    required int qualifying,
    required int readingsSeen,
    required int unattributed,
    required int shown,
  }) {
    final unit = spec.measure.unit == null ? '' : ' ${spec.measure.unit}';
    return MetricExplanation(
      title: 'Ranked by ${spec.measure.label.toLowerCase()}',
      summary: 'Computed on this device from $readingsSeen recorded '
          '${readingsSeen == 1 ? 'value' : 'values'}.',
      method: <String>[
        'Each patient counts once, by their single '
            '${spec.descending ? 'highest' : 'lowest'} recorded value — '
            'ranking raw readings would fill the list with whoever was '
            'measured most often.',
        if (spec.cutoff case final cutoff?)
          '${spec.qualifier == null ? 'The threshold' : '"${spec.qualifier}"'} '
              'was read as ${Fmt.stat(cutoff)}$unit '
              '${spec.descending ? 'or more' : 'or less'} — a published '
              'screening cut-off, shown so it can be argued with.',
        'These are measured readings, not diagnoses. One reading beyond a '
            'threshold is a reading; the problem list is a different '
            'question, and the two can legitimately disagree.',
        if (unattributed > 0)
          '$unattributed ${unattributed == 1 ? 'reading' : 'readings'} '
              'belonged to no patient record and were left out.',
      ],
      derivation: <ExplainRow>[
        ExplainRow(label: 'Readings seen', value: '$readingsSeen'),
        ExplainRow(label: 'Patients qualifying', value: '$qualifying'),
        ExplainRow(label: 'Shown', value: '$shown'),
      ],
      total: '$qualifying',
      confidence: ExplainConfidence.measured,
      caveat: 'It ranks what is recorded, not what is true. A patient whose '
          'reading was never entered is not on this list, however unwell.',
    );
  }

  static String _headline(RankSpec spec, int qualifying) {
    final measure = spec.measure.label.toLowerCase();
    if (spec.cutoff case final cutoff?) {
      final unit = spec.measure.unit == null ? '' : ' ${spec.measure.unit}';
      final bound = spec.descending ? 'or more' : 'or less';
      final read = spec.qualifier == null
          ? ''
          : '"${spec.qualifier}" read as ';
      return '$qualifying ${qualifying == 1 ? 'patient has' : 'patients have'} '
          'a recorded $measure of $read${Fmt.stat(cutoff)}$unit $bound — '
          'measured readings, not diagnoses.';
    }
    return 'Top ${spec.limit} by $measure — each patient\'s '
        '${spec.descending ? 'highest' : 'lowest'} recorded value.';
  }

  static DateTime? _instant(Object? raw) => switch (raw) {
        final int epoch => DateTime.fromMillisecondsSinceEpoch(epoch),
        final String iso => DateTime.tryParse(iso),
        _ => null,
      };
}
