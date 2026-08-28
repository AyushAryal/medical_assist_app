import 'package:flutter/material.dart';

import '../../core/design/design.dart';

import '../../clinical/calculations.dart';
import '../../clinical/metric_explanations.dart';
import '../../clinical/news2.dart';
import '../../clinical/patient_age.dart';
import '../../clinical/vital_reference.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/vitals_record.dart';

/// The latest observation set, flagged against the patient's age band and with
/// deltas against the previous set.
class VitalsSummaryCard extends StatelessWidget {
  const VitalsSummaryCard({
    super.key,
    required this.vitals,
    this.previous,
    required this.age,
    this.onTap,
    this.onRecord,
  });

  final VitalsRecord vitals;
  final VitalsRecord? previous;
  final PatientAge? age;
  final VoidCallback? onTap;
  final VoidCallback? onRecord;

  String? _delta(num? current, num? before, {int decimals = 0}) {
    if (current == null || before == null) return null;
    final difference = current - before;
    if (difference == 0) return '=';
    final arrow = difference > 0 ? '▲' : '▼';
    return '$arrow${difference.abs().toStringAsFixed(decimals)}';
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final flags = vitals.flags(age);
    final map = ClinicalCalc.meanArterialPressure(
      systolic: vitals.systolicBp,
      diastolic: vitals.diastolicBp,
    );

    // The worse of the two BP flags drives how the pair is coloured — a
    // systolic of 200 must not read as normal because the diastolic is fine.
    final bpFlag = <VitalFlag>[flags['systolic']!, flags['diastolic']!]
        .reduce((a, b) => a.index < b.index ? a : b);

    final tiles = <Widget>[
      if (vitals.bloodPressure != null)
        VitalValue(
          label: 'BP',
          value: vitals.bloodPressure!,
          unit: 'mmHg',
          flag: bpFlag,
          reference: map == null ? null : 'MAP ${map.toStringAsFixed(0)}',
          delta: _delta(vitals.systolicBp, previous?.systolicBp),
          // The pair is coloured by the worse of its two flags, so the
          // explanation is for whichever one that was — otherwise a systolic
          // of 200 would be explained by a perfectly normal diastolic.
          explanation: bpFlag == flags['systolic']
              ? MetricExplanations.referenceRange(
                  label: 'Systolic blood pressure',
                  value: '${vitals.systolicBp}',
                  unit: 'mmHg',
                  range: VitalReference.systolic(age),
                  flag: flags['systolic']!,
                  age: age,
                  ageBanded: true,
                )
              : MetricExplanations.referenceRange(
                  label: 'Diastolic blood pressure',
                  value: '${vitals.diastolicBp}',
                  unit: 'mmHg',
                  range: VitalReference.diastolic(age),
                  flag: flags['diastolic']!,
                  age: age,
                  ageBanded: true,
                ),
        ),
      if (map != null)
        VitalValue(
          label: 'MAP',
          value: map.toStringAsFixed(0),
          unit: 'mmHg',
          compact: true,
          explanation: MetricExplanations.meanArterialPressure(
            systolic: vitals.systolicBp!,
            diastolic: vitals.diastolicBp!,
            map: map,
          ),
        ),
      if (vitals.heartRate != null)
        VitalValue(
          label: 'Pulse',
          value: '${vitals.heartRate}',
          unit: 'bpm',
          flag: flags['heartRate']!,
          reference: VitalReference.heartRate(age).display,
          delta: _delta(vitals.heartRate, previous?.heartRate),
          explanation: MetricExplanations.referenceRange(
            label: 'Pulse',
            value: '${vitals.heartRate}',
            unit: 'bpm',
            range: VitalReference.heartRate(age),
            flag: flags['heartRate']!,
            age: age,
            ageBanded: true,
          ),
        ),
      if (vitals.respiratoryRate != null)
        VitalValue(
          label: 'Resp',
          value: '${vitals.respiratoryRate}',
          unit: '/min',
          flag: flags['respiratoryRate']!,
          reference: VitalReference.respiratoryRate(age).display,
          delta: _delta(vitals.respiratoryRate, previous?.respiratoryRate),
          explanation: MetricExplanations.referenceRange(
            label: 'Respiratory rate',
            value: '${vitals.respiratoryRate}',
            unit: 'breaths/min',
            range: VitalReference.respiratoryRate(age),
            flag: flags['respiratoryRate']!,
            age: age,
            ageBanded: true,
          ),
        ),
      if (vitals.spo2 != null)
        VitalValue(
          label: 'SpO₂',
          value: '${vitals.spo2}',
          unit: '%',
          flag: flags['spo2']!,
          reference: vitals.onOxygen
              ? 'on O₂${vitals.oxygenFlowLpm == null ? '' : ' '
                  '${Fmt.number(vitals.oxygenFlowLpm)} L'}'
              : 'room air',
          delta: _delta(vitals.spo2, previous?.spo2),
          explanation: MetricExplanations.referenceRange(
            label: 'Oxygen saturation',
            value: '${vitals.spo2}',
            unit: '%',
            range: VitalReference.spo2,
            flag: flags['spo2']!,
            age: age,
          ),
        ),
      if (vitals.temperatureC != null)
        VitalValue(
          label: 'Temp',
          value: Fmt.number(vitals.temperatureC),
          unit: '°C',
          flag: flags['temperature']!,
          reference: vitals.temperatureSite?.label,
          delta: _delta(vitals.temperatureC, previous?.temperatureC, decimals: 1),
          explanation: MetricExplanations.referenceRange(
            label: 'Temperature',
            value: Fmt.number(vitals.temperatureC),
            unit: '°C',
            range: VitalReference.temperature,
            flag: flags['temperature']!,
            age: age,
          ),
        ),
      if (vitals.painScore != null)
        VitalValue(
          label: 'Pain',
          value: '${vitals.painScore}',
          unit: '/10',
          flag: flags['pain']!,
          delta: _delta(vitals.painScore, previous?.painScore),
        ),
      if (vitals.bloodGlucoseMmol != null)
        VitalValue(
          label: 'Glucose',
          value: Fmt.number(vitals.bloodGlucoseMmol),
          unit: 'mmol/L',
          flag: flags['glucose']!,
          reference: vitals.glucoseTiming,
          explanation: MetricExplanations.referenceRange(
            label: 'Blood glucose',
            value: Fmt.number(vitals.bloodGlucoseMmol),
            unit: 'mmol/L',
            range: VitalReference.bloodGlucoseMmol,
            flag: flags['glucose']!,
            age: age,
          ),
        ),
      if (vitals.weightKg != null)
        VitalValue(
          label: 'Weight',
          value: Fmt.number(vitals.weightKg),
          unit: 'kg',
          reference: vitals.bmi == null
              ? null
              : 'BMI ${Fmt.number(vitals.bmi)}',
          delta: _delta(vitals.weightKg, previous?.weightKg, decimals: 1),
          explanation: (vitals.bmi == null || vitals.heightCm == null)
              ? null
              : MetricExplanations.bmi(
                  weightKg: vitals.weightKg!,
                  heightCm: vitals.heightCm!,
                  bmi: vitals.bmi!,
                  classification: ClinicalCalc.bmiClass(vitals.bmi, age),
                  age: age,
                ),
        ),
    ];

    return SectionCard(
      title: 'Latest observations',
      subtitle: '${Fmt.relative(vitals.recordedAt)}'
          '${vitals.recordedBy == null ? '' : ' · ${vitals.recordedBy}'}',
      leading: const Icon(Icons.monitor_heart_outlined, size: 20),
      trailing: onRecord == null
          ? null
          : IconButton(
              tooltip: 'Record new observations',
              icon: const Icon(Icons.add),
              onPressed: onRecord,
            ),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // A width-filling grid rather than a left-packed wrap: a handful of
          // tiles used to trail off in one row leaving the right of the card
          // empty. Columns scale with the card's width — two on a phone, more
          // on a tablet — so the space is used at either size.
          AdaptiveColumns(
            minColumnWidth: 150,
            maxColumns: 4,
            spacing: m.spaceLg,
            children: tiles,
          ),
          if (vitals.news2Score != null) ...<Widget>[
            SizedBox(height: m.spaceLg),
            _News2Strip(vitals: vitals, age: age),
          ],
          if (vitals.notes?.isNotEmpty == true) ...<Widget>[
            SizedBox(height: m.spaceMd),
            Text(vitals.notes!, style: context.texts.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _News2Strip extends StatelessWidget {
  const _News2Strip({required this.vitals, required this.age});

  final VitalsRecord vitals;
  final PatientAge? age;

  /// Re-derives the per-parameter breakdown.
  ///
  /// Only the total and the risk band are stored, because those are what the
  /// clinician acted on and they must never change retrospectively. The
  /// breakdown is a pure function of the same row, so recomputing it is safe —
  /// and [MetricExplanations.news2] checks the stored algorithm version before
  /// presenting it, so a score taken under an older version is shown as it was
  /// rather than re-explained under today's rules.
  MetricExplanation _explanation() {
    final result = News2Calculator.score(
      ageYears: age?.years,
      // A record that carries a score was, by definition, in scope when it was
      // taken — the calculator refuses to score a pregnant patient at all.
      isPregnant: false,
      input: vitals.news2Input,
    );

    return MetricExplanations.news2(
      result: result,
      storedAlgorithmVersion: vitals.news2Algorithm,
      storedTotal: vitals.news2Score,
      onOxygen: vitals.onOxygen,
      measuredValues: <String, String>{
        'Respiration rate': vitals.respiratoryRate == null
            ? 'not recorded'
            : '${vitals.respiratoryRate} breaths/min',
        'SpO₂': vitals.spo2 == null ? 'not recorded' : '${vitals.spo2}%',
        'Systolic BP': vitals.systolicBp == null
            ? 'not recorded'
            : '${vitals.systolicBp} mmHg',
        'Pulse':
            vitals.heartRate == null ? 'not recorded' : '${vitals.heartRate} bpm',
        'Consciousness': vitals.consciousness == null
            ? 'not recorded'
            : '${vitals.consciousness!.label} '
                '(${vitals.consciousness!.code})',
        'Temperature': vitals.temperatureC == null
            ? 'not recorded'
            : '${Fmt.number(vitals.temperatureC)} °C',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final risk = News2Risk.values
        .where((r) => r.name == vitals.news2Risk)
        .firstOrNull;

    final tone = switch (risk) {
      News2Risk.high => PillTone.critical,
      News2Risk.medium => PillTone.caution,
      News2Risk.lowMedium => PillTone.caution,
      _ => PillTone.normal,
    };

    return Container(
      padding: EdgeInsets.all(m.spaceMd),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
        border: Border.all(color: palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('NEWS2', style: context.texts.labelLarge),
              InfoDot(
                explanation: _explanation(),
                semanticLabel: 'How this early warning score was reached',
              ),
              SizedBox(width: m.spaceXs),
              StatusPill(
                label: '${vitals.news2Score} · ${risk?.label ?? ''} risk',
                tone: tone,
                dense: true,
              ),
            ],
          ),
          if (risk != null) ...<Widget>[
            SizedBox(height: m.spaceXs),
            Text(risk.response, style: context.texts.bodySmall),
          ],
          SizedBox(height: m.spaceXs),
          Text(
            'Decision support only — escalation remains a clinical judgement.',
            style: context.texts.labelSmall,
          ),
        ],
      ),
    );
  }
}
