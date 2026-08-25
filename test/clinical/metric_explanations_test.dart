import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/explanations.dart';
import 'package:medical_app/clinical/metric_explanations.dart';
import 'package:medical_app/clinical/news2.dart';
import 'package:medical_app/clinical/patient_age.dart';
import 'package:medical_app/clinical/vital_reference.dart';

void main() {
  const values = <String, String>{
    'Respiration rate': '22 breaths/min',
    'SpO₂': '94%',
    'Systolic BP': '105 mmHg',
    'Pulse': '115 bpm',
    'Consciousness': 'Alert (A)',
    'Temperature': '38.5 °C',
  };

  News2Result requireScore() {
    final result = News2Calculator.score(
      ageYears: 40,
      isPregnant: false,
      input: const News2Input(
        respiratoryRate: 22,
        spo2: 94,
        systolicBp: 105,
        heartRate: 115,
        consciousness: Consciousness.alert,
        temperatureC: 38.5,
      ),
    );
    expect(result, isNotNull, reason: 'this input is inside NEWS2 scope');
    return result!;
  }

  group('NEWS2 explanation', () {
    test('shows every parameter with what it contributed', () {
      final result = requireScore();
      final explanation = MetricExplanations.news2(
        result: result,
        measuredValues: values,
        storedAlgorithmVersion: News2Calculator.algorithmVersion,
      );

      // The breakdown is the point: a clinician must be able to see *what*
      // drove the score, not just the total.
      expect(explanation.derivation, hasLength(7));
      expect(
        explanation.derivation.map((r) => r.label),
        containsAll(<String>['Respiration rate', 'Pulse', 'Temperature']),
      );
      expect(explanation.total, contains('${result.total}'));
      expect(explanation.confidence, ExplainConfidence.validated);
    });

    test('the contributions sum to the stated total', () {
      final result = requireScore();
      final explanation = MetricExplanations.news2(
        result: result,
        measuredValues: values,
      );

      final summed = explanation.derivation
          .map((r) => int.parse(r.contribution!.replaceAll('+', '')))
          .fold<int>(0, (sum, v) => sum + v);

      expect(summed, result.total);
    });

    test('each row carries the measurement that produced it', () {
      final explanation = MetricExplanations.news2(
        result: requireScore(),
        measuredValues: values,
      );

      final pulse =
          explanation.derivation.firstWhere((r) => r.label == 'Pulse');
      expect(pulse.value, '115 bpm');
    });

    test('air or oxygen is described rather than left blank', () {
      final onOxygen = MetricExplanations.news2(
        result: requireScore(),
        measuredValues: values,
        onOxygen: true,
      );
      final onAir = MetricExplanations.news2(
        result: requireScore(),
        measuredValues: values,
      );

      expect(
        onOxygen.derivation
            .firstWhere((r) => r.label == 'Air or oxygen')
            .value,
        'On supplemental oxygen',
      );
      expect(
        onAir.derivation.firstWhere((r) => r.label == 'Air or oxygen').value,
        'Breathing air',
      );
    });

    test('a parameter scoring 3 is called out as escalating on its own', () {
      final result = News2Calculator.score(
        ageYears: 40,
        isPregnant: false,
        input: const News2Input(
          respiratoryRate: 30, // scores 3
          spo2: 96,
          systolicBp: 120,
          heartRate: 70,
          consciousness: Consciousness.alert,
          temperatureC: 37,
        ),
      )!;

      final explanation = MetricExplanations.news2(
        result: result,
        measuredValues: <String, String>{'Respiration rate': '30 breaths/min'},
      );

      final row = explanation.derivation
          .firstWhere((r) => r.label == 'Respiration rate');
      expect(row.note, contains('triggers escalation'));
    });

    test('a historic score under an older algorithm is not re-explained', () {
      // The stored total is what the clinician acted on. Re-deriving it under
      // today's rules could display a different number than the one in the
      // record, which is worse than declining to explain it.
      final explanation = MetricExplanations.news2(
        result: requireScore(),
        measuredValues: values,
        storedAlgorithmVersion: 'NEWS2-SOMETHING-2015',
        storedTotal: 4,
      );

      expect(explanation.derivation, isEmpty);
      expect(explanation.caveat, contains('NEWS2-SOMETHING-2015'));
      expect(explanation.summary, contains('4'));
    });

    test('an unscorable set explains why rather than showing zero', () {
      final explanation = MetricExplanations.news2(
        result: null,
        measuredValues: const <String, String>{},
      );

      expect(explanation.derivation, isEmpty);
      expect(explanation.caveat, contains('incomplete'));
      expect(explanation.method, isNotEmpty);
    });

    test('always states the scope it is not validated for', () {
      final explanation = MetricExplanations.news2(
        result: requireScore(),
        measuredValues: values,
      );

      expect(explanation.caveat, contains('pregnancy'));
      expect(explanation.caveat, contains('16'));
    });
  });

  group('reference range explanation', () {
    test('names the age band that was applied', () {
      final age = PatientAge.fromDateOfBirth(
        DateTime(2020, 1, 1),
        asOf: DateTime(2026, 1, 1),
      );

      final explanation = MetricExplanations.referenceRange(
        label: 'Pulse',
        value: '140',
        unit: 'bpm',
        range: VitalReference.heartRate(age),
        flag: VitalFlag.high,
        age: age,
        ageBanded: true,
      );

      expect(explanation.method.first, contains('6y'));
      expect(explanation.method.first, contains('5–12 years'));
    });

    test('says so when no age is recorded and the adult band was used', () {
      final explanation = MetricExplanations.referenceRange(
        label: 'Pulse',
        value: '140',
        unit: 'bpm',
        range: VitalReference.heartRate(null),
        flag: VitalFlag.high,
        ageBanded: true,
      );

      expect(explanation.method.first, contains('adult band was used'));
    });

    test('a normal reading is still explained', () {
      final explanation = MetricExplanations.referenceRange(
        label: 'Temperature',
        value: '37.0',
        unit: '°C',
        range: VitalReference.temperature,
        flag: VitalFlag.normal,
      );

      expect(explanation.summary, contains('inside the reference band'));
      expect(explanation.derivation, isNotEmpty);
    });

    test('warns that a value inside the band is not reassurance', () {
      final explanation = MetricExplanations.referenceRange(
        label: 'Pulse',
        value: '80',
        unit: 'bpm',
        range: VitalReference.heartRate(null),
        flag: VitalFlag.normal,
      );

      expect(explanation.caveat, contains('does not mean the patient is well'));
    });
  });

  group('bedside calculations', () {
    test('MAP shows the arithmetic', () {
      final explanation = MetricExplanations.meanArterialPressure(
        systolic: 120,
        diastolic: 80,
        map: 93.3,
      );

      expect(explanation.total, '93 mmHg');
      expect(
        explanation.derivation.map((r) => r.value).join(' '),
        contains('(120 + 2 × 80) ÷ 3'),
      );
      expect(explanation.caveat, contains('tachycardia'));
    });

    test('BMI refuses to categorise a child', () {
      final child = PatientAge.fromDateOfBirth(
        DateTime(2016, 1, 1),
        asOf: DateTime(2026, 1, 1),
      );

      final explanation = MetricExplanations.bmi(
        weightKg: 30,
        heightCm: 135,
        bmi: 16.5,
        age: child,
      );

      // A raw BMI means little in children without a centile chart, and this
      // app does not hold one. Saying so beats printing a category.
      expect(explanation.confidence, ExplainConfidence.heuristic);
      expect(explanation.caveat, contains('centile'));
    });

    test('BMI categorises an adult', () {
      final explanation = MetricExplanations.bmi(
        weightKg: 70,
        heightCm: 175,
        bmi: 22.9,
        classification: 'Normal',
      );

      expect(explanation.confidence, ExplainConfidence.measured);
      expect(
        explanation.derivation.map((r) => r.label),
        contains('Category'),
      );
    });
  });

  group('trend explanation', () {
    test('reports insufficient data below three readings', () {
      final explanation = MetricExplanations.trend(
        label: 'Pulse',
        pointCount: 2,
        firstValue: '70 bpm',
        lastValue: '95 bpm',
        span: '2 weeks',
      );

      expect(explanation.confidence, ExplainConfidence.insufficientData);
      expect(explanation.caveat, contains('not a trend'));
    });

    test('explains that a sparkline is scaled to itself', () {
      final explanation = MetricExplanations.trend(
        label: 'Pulse',
        pointCount: 6,
        firstValue: '70 bpm',
        lastValue: '118 bpm',
        span: '3 months',
      );

      expect(
        explanation.method.join(' '),
        contains('never comparable to each other'),
      );
    });
  });
}
