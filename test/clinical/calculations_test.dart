import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/calculations.dart';
import 'package:medical_app/clinical/patient_age.dart';

void main() {
  PatientAge ageOf(int years) => PatientAge.fromDateOfBirth(
        DateTime(2026 - years, 6, 15),
        asOf: DateTime(2026, 6, 15),
      )!;

  group('BMI', () {
    test('computes kg/m squared', () {
      expect(
        ClinicalCalc.bmi(weightKg: 70, heightCm: 175),
        closeTo(22.86, 0.01),
      );
    });

    test('rejects implausible inputs rather than guessing', () {
      // Height entered in metres instead of centimetres.
      expect(ClinicalCalc.bmi(weightKg: 70, heightCm: 1.75), isNull);
      // Weight entered in grams.
      expect(ClinicalCalc.bmi(weightKg: 70000, heightCm: 175), isNull);
      expect(ClinicalCalc.bmi(weightKg: 70, heightCm: null), isNull);
    });

    test('defers to paediatric centiles under 20', () {
      expect(ClinicalCalc.bmiClass(22, ageOf(12)), 'Use paediatric centiles');
      expect(ClinicalCalc.bmiClass(22, ageOf(30)), 'Normal');
      expect(ClinicalCalc.bmiClass(31, ageOf(30)), 'Obese I');
    });
  });

  group('haemodynamics', () {
    test('MAP is diastolic plus a third of the pulse pressure', () {
      expect(
        ClinicalCalc.meanArterialPressure(systolic: 120, diastolic: 80),
        closeTo(93.33, 0.01),
      );
    });

    test('rejects a diastolic at or above the systolic', () {
      expect(
        ClinicalCalc.meanArterialPressure(systolic: 80, diastolic: 90),
        isNull,
      );
      expect(ClinicalCalc.pulsePressure(systolic: 80, diastolic: 80), isNull);
    });

    test('shock index rises with occult compromise', () {
      expect(
        ClinicalCalc.shockIndex(heartRate: 70, systolic: 120),
        closeTo(0.583, 0.001),
      );
      expect(
        ClinicalCalc.shockIndex(heartRate: 110, systolic: 100),
        closeTo(1.1, 0.001),
      );
    });
  });

  group('blood pressure category', () {
    test('stages an adult office reading', () {
      expect(
        ClinicalCalc.bloodPressureCategory(systolic: 185, diastolic: 95),
        'Hypertensive crisis',
      );
      expect(
        ClinicalCalc.bloodPressureCategory(systolic: 145, diastolic: 85),
        'Stage 2 hypertension',
      );
      expect(
        ClinicalCalc.bloodPressureCategory(systolic: 132, diastolic: 78),
        'Stage 1 hypertension',
      );
      expect(
        ClinicalCalc.bloodPressureCategory(systolic: 124, diastolic: 76),
        'Elevated',
      );
      expect(
        ClinicalCalc.bloodPressureCategory(systolic: 112, diastolic: 70),
        'Normal',
      );
      expect(
        ClinicalCalc.bloodPressureCategory(systolic: 85, diastolic: 55),
        'Hypotension',
      );
    });

    test('declines to stage a child', () {
      expect(
        ClinicalCalc.bloodPressureCategory(
          systolic: 145,
          diastolic: 85,
          age: ageOf(9),
        ),
        isNull,
      );
    });
  });

  group('unit conversion', () {
    test('round-trips temperature', () {
      expect(ClinicalCalc.fahrenheitToCelsius(98.6), closeTo(37.0, 0.01));
      expect(ClinicalCalc.celsiusToFahrenheit(37.0), closeTo(98.6, 0.01));
    });

    test('round-trips glucose', () {
      expect(ClinicalCalc.mgDlToMmolGlucose(180), closeTo(9.99, 0.01));
      expect(ClinicalCalc.mmolToMgDlGlucose(10), closeTo(180.18, 0.01));
    });
  });

  test('paediatric weight estimate follows the APLS formulas', () {
    // 1-5 years: 2 x (age + 4).
    expect(ClinicalCalc.estimatedWeightKg(ageOf(3)), 14);
    // 6-11 years: 4 x age.
    expect(ClinicalCalc.estimatedWeightKg(ageOf(8)), 32);
    // Not offered for adolescents and adults.
    expect(ClinicalCalc.estimatedWeightKg(ageOf(14)), isNull);
  });
}
