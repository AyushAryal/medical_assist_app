import 'explanations.dart';
import 'news2.dart';
import 'patient_age.dart';
import 'vital_reference.dart';

/// Builds the "where did this number come from?" text for every derived value
/// the UI displays.
///
/// Kept in one file on purpose. When a threshold changes, the explanation must
/// change with it, and the only way to guarantee that is for the rule and its
/// account of itself to live next to each other. An explanation that has
/// drifted from the code is worse than none — it is a confident lie.
abstract final class MetricExplanations {
  // ---------------------------------------------------------------------------
  // NEWS2
  // ---------------------------------------------------------------------------

  /// The full working for an early warning score: every parameter, the band it
  /// fell into, and what it contributed to the total.
  ///
  /// [result] is recomputed from the stored observation set rather than read
  /// back from the database, because only the total and the risk band are
  /// persisted. Recomputing is safe here — the score is a pure function of the
  /// row, and [News2Result.algorithmVersion] is checked against the version
  /// stamped on the record so a historic score is never re-explained under
  /// today's rules.
  static MetricExplanation news2({
    required News2Result? result,
    required Map<String, String> measuredValues,
    String? storedAlgorithmVersion,
    int? storedTotal,
    bool onOxygen = false,
    bool useSpo2Scale2 = false,
  }) {
    final versionMatches = storedAlgorithmVersion == null ||
        storedAlgorithmVersion == News2Calculator.algorithmVersion;

    if (result == null || !versionMatches) {
      return MetricExplanation(
        title: 'NEWS2',
        summary: storedTotal == null
            ? 'A score of 0–20 summarising how far seven observations sit from '
                'normal adult physiology.'
            : 'This record scored $storedTotal when it was taken.',
        method: const <String>[
          'Each of seven parameters scores 0, 1, 2 or 3 against published '
              'bands.',
          'The seven scores are added together to give the total.',
          'A single parameter scoring 3 triggers escalation on its own, even '
              'when the total is low.',
        ],
        confidence: ExplainConfidence.validated,
        source: 'Royal College of Physicians, NEWS2 (2017)',
        caveat: versionMatches
            ? 'The per-parameter breakdown needs all seven observations. This '
                'set is incomplete, so only the parameters that were recorded '
                'can be shown.'
            : 'This score was calculated by algorithm version '
                '$storedAlgorithmVersion, which is not the version running '
                'now. The stored total is shown unchanged; re-deriving it under '
                "today's rules could show a different number than the one the "
                'clinician acted on.',
      );
    }

    final rows = <ExplainRow>[
      for (final entry in result.parameterScores.entries)
        ExplainRow(
          label: entry.key,
          value: entry.key == 'Air or oxygen'
              ? (onOxygen ? 'On supplemental oxygen' : 'Breathing air')
              : measuredValues[entry.key] ?? 'not recorded',
          contribution: '+${entry.value}',
          note: entry.value >= 3
              ? 'Scores 3 on its own — triggers escalation regardless of total'
              : entry.value == 0
                  ? 'Within the normal band'
                  : null,
        ),
    ];

    return MetricExplanation(
      title: 'NEWS2 — how this score was reached',
      summary:
          'Seven observations are each scored 0–3 against published bands and '
          'added up. Higher means further from normal adult physiology, and the '
          'total maps onto a recommended monitoring frequency.',
      method: <String>[
        'Each parameter is scored against its NEWS2 band (shown below).',
        'The seven scores are added: total ${result.total}.',
        if (result.hasSingleParameterThree)
          'One parameter scored 3, which raises the risk band on its own.',
        'Total 0–4 is low, 5–6 medium, 7 or more high. A single 3 makes an '
            'otherwise-low total low–medium.',
        'This total falls in the ${result.risk.label.toLowerCase()} band.',
        if (useSpo2Scale2)
          'SpO₂ was scored on Scale 2 (target 88–92%), which must be '
              'prescribed per patient for chronic hypercapnic respiratory '
              'failure.',
      ],
      derivation: rows,
      total: '${result.total} of 20 — ${result.risk.label} risk',
      confidence: ExplainConfidence.validated,
      source: 'Royal College of Physicians, NEWS2 (2017) · '
          'algorithm ${result.algorithmVersion}',
      caveat: 'Validated for acutely ill adults aged 16 and over. It is not '
          'validated in pregnancy or in children, and this app refuses to score '
          'those patients rather than show a misleading number. Escalation '
          'remains a clinical judgement and local policy always takes '
          'precedence.',
    );
  }

  // ---------------------------------------------------------------------------
  // Reference ranges
  // ---------------------------------------------------------------------------

  /// Why one observation is flagged H, L, HH or LL.
  static MetricExplanation referenceRange({
    required String label,
    required String value,
    required String unit,
    required VitalRange range,
    required VitalFlag flag,
    PatientAge? age,
    bool ageBanded = false,
  }) {
    return MetricExplanation(
      title: '$label — $value $unit',
      summary: flag == VitalFlag.normal
          ? 'This reading sits inside the reference band for this patient.'
          : 'This reading sits ${flag.label.toLowerCase()} for this patient, '
              'which is why it is marked ${flag.shortLabel}.',
      method: <String>[
        if (ageBanded && age != null)
          'The band is chosen by age: this patient is ${age.label}, '
              'so the ${_ageBandName(age)} band applies.'
        else if (ageBanded)
          'This band is normally chosen by age, but no date of birth or '
              'approximate age is recorded, so the adult band was used.'
        else
          'The same band applies at every age.',
        'Normal for this band is ${range.display} $unit.',
        if (range.criticalLow != null)
          'At or below ${_num(range.criticalLow!)} $unit the value is marked '
              'LL — critically low.',
        if (range.criticalHigh != null)
          'At or above ${_num(range.criticalHigh!)} $unit the value is marked '
              'HH — critically high.',
        'Outside the normal band but short of those thresholds is marked '
            'H or L.',
      ],
      derivation: <ExplainRow>[
        ExplainRow(label: 'Recorded', value: '$value $unit'),
        ExplainRow(
          label: 'Normal band',
          value: '${range.display} $unit',
          note: ageBanded ? 'age-banded' : 'all ages',
        ),
        if (range.criticalLow != null)
          ExplainRow(
            label: 'Critical low',
            value: '≤ ${_num(range.criticalLow!)} $unit',
          ),
        if (range.criticalHigh != null)
          ExplainRow(
            label: 'Critical high',
            value: '≥ ${_num(range.criticalHigh!)} $unit',
          ),
        ExplainRow(
          label: 'Result',
          value: flag == VitalFlag.normal ? 'Normal' : flag.label,
          contribution: flag.shortLabel.isEmpty ? null : flag.shortLabel,
        ),
      ],
      confidence: ExplainConfidence.validated,
      source: ageBanded
          ? 'APLS/PALS age bands; adult ranges as widely taught'
          : 'Standard adult reference ranges',
      caveat: 'These are population ranges for a resting, afebrile patient. A '
          'value inside the band does not mean the patient is well, and a '
          'value outside it does not by itself mean they are unwell — it means '
          'look closer.',
    );
  }

  static String _ageBandName(PatientAge age) {
    if (age.isNeonate) return 'neonatal';
    if (age.isInfant) return 'infant';
    if (age.years < 2) return '1–2 years';
    if (age.years < 5) return '2–5 years';
    if (age.years < 12) return '5–12 years';
    if (age.years < 16) return '12–16 years';
    return 'adult';
  }

  // ---------------------------------------------------------------------------
  // Bedside calculations
  // ---------------------------------------------------------------------------

  static MetricExplanation meanArterialPressure({
    required int systolic,
    required int diastolic,
    required double map,
  }) {
    return MetricExplanation(
      title: 'MAP — mean arterial pressure',
      summary: 'The average pressure perfusing the organs over one cardiac '
          'cycle. Below about 65 mmHg, perfusion of the kidneys and brain '
          'starts to fall.',
      method: const <String>[
        'The heart spends roughly twice as long in diastole as in systole, so '
            'diastolic pressure is weighted double.',
        'MAP = (systolic + 2 × diastolic) ÷ 3',
      ],
      derivation: <ExplainRow>[
        ExplainRow(label: 'Systolic', value: '$systolic mmHg'),
        ExplainRow(
          label: 'Diastolic',
          value: '$diastolic mmHg',
          note: 'counted twice',
        ),
        ExplainRow(
          label: 'Calculation',
          value: '($systolic + 2 × $diastolic) ÷ 3',
        ),
      ],
      total: '${map.toStringAsFixed(0)} mmHg',
      source: 'Standard bedside approximation',
      caveat: 'An approximation that assumes a normal heart rate. It becomes '
          'unreliable in marked tachycardia, where diastole shortens.',
    );
  }

  static MetricExplanation bmi({
    required double weightKg,
    required double heightCm,
    required double bmi,
    String? classification,
    PatientAge? age,
  }) {
    final isChild = age != null && age.isChild;
    return MetricExplanation(
      title: 'BMI — body mass index',
      summary: 'Weight scaled to height, so two people of different sizes can '
          'be compared on one number.',
      method: const <String>[
        'Height is converted from centimetres to metres.',
        'BMI = weight in kg ÷ (height in metres)²',
      ],
      derivation: <ExplainRow>[
        ExplainRow(label: 'Weight', value: '${_num(weightKg)} kg'),
        ExplainRow(
          label: 'Height',
          value: '${_num(heightCm)} cm',
          note: '${(heightCm / 100).toStringAsFixed(2)} m',
        ),
        ExplainRow(
          label: 'Calculation',
          value: '${_num(weightKg)} ÷ '
              '${(heightCm / 100).toStringAsFixed(2)}²',
        ),
        if (classification != null)
          ExplainRow(label: 'Category', value: classification),
      ],
      total: bmi.toStringAsFixed(1),
      confidence:
          isChild ? ExplainConfidence.heuristic : ExplainConfidence.measured,
      source: isChild
          ? 'Adult BMI formula — paediatric interpretation needs a centile chart'
          : 'WHO adult BMI categories',
      caveat: isChild
          ? 'This patient is ${age.label}. A raw BMI number means little in '
              'children — it has to be read against an age-and-sex centile '
              'chart, which this app does not yet hold. The figure is shown '
              'for continuity of measurement only, and no category is applied.'
          : 'BMI does not distinguish muscle from fat, and it reads high in '
              'muscular people and low in older people who have lost muscle.',
    );
  }

  // ---------------------------------------------------------------------------
  // Trends
  // ---------------------------------------------------------------------------

  /// Explains a sparkline and the delta beside it.
  static MetricExplanation trend({
    required String label,
    required int pointCount,
    required String firstValue,
    required String lastValue,
    required String span,
    String? slopeDescription,
  }) {
    return MetricExplanation(
      title: '$label — trend',
      summary: 'Direction over time. A value climbing steadily matters even '
          'while every individual reading is still inside its reference band.',
      method: <String>[
        'Every recorded value for this observation is plotted oldest to '
            'newest — $pointCount points spanning $span.',
        'The line is scaled to its own minimum and maximum, so it shows shape, '
            'not absolute height. Two sparklines are never comparable to each '
            'other.',
        'Gaps where the observation was not taken are skipped, not '
            'interpolated — the line joins the readings that exist.',
        'The number to the right is the most recent value, not an average.',
        ?slopeDescription,
      ],
      derivation: <ExplainRow>[
        ExplainRow(label: 'Oldest', value: firstValue),
        ExplainRow(label: 'Most recent', value: lastValue),
        ExplainRow(label: 'Readings', value: '$pointCount over $span'),
      ],
      confidence: pointCount < 3
          ? ExplainConfidence.insufficientData
          : ExplainConfidence.measured,
      caveat: pointCount < 3
          ? 'Two readings make a line, not a trend. Direction only becomes '
              'meaningful from about three points onward.'
          : 'Readings taken in different circumstances — after exertion, on '
              'oxygen, on treatment — sit on the same line. The shape can be '
              'explained by context that the chart does not show.',
    );
  }

  static String _num(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}
