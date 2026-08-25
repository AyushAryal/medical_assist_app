import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/patient_age.dart';
import 'package:medical_app/clinical/vital_reference.dart';

/// Age banding is the difference between "this infant is fine" and "this
/// infant is bradycardic". These tests pin the bands so a refactor cannot
/// quietly apply adult ranges to a child.
void main() {
  PatientAge ageOf({int years = 0, int months = 0}) {
    final now = DateTime(2026, 6, 15);
    final dob = DateTime(now.year - years, now.month - months, now.day);
    return PatientAge.fromDateOfBirth(dob, asOf: now)!;
  }

  group('PatientAge', () {
    test('computes years, months and days', () {
      final age = PatientAge.fromDateOfBirth(
        DateTime(1990, 3, 20),
        asOf: DateTime(2026, 6, 15),
      )!;
      expect(age.years, 36);
      expect(age.months, 2);
      expect(age.days, 26);
    });

    test('handles a birthday later this month', () {
      final age = PatientAge.fromDateOfBirth(
        DateTime(1990, 6, 20),
        asOf: DateTime(2026, 6, 15),
      )!;
      expect(age.years, 35);
      expect(age.months, 11);
    });

    test('labels neonates in days and infants in months', () {
      expect(
        PatientAge.fromDateOfBirth(
          DateTime(2026, 6, 1),
          asOf: DateTime(2026, 6, 15),
        )!.label,
        '14 d',
      );
      expect(ageOf(months: 7).label, '7 mo');
      expect(ageOf(years: 40).label, '40y');
    });

    test('rejects a future date of birth', () {
      expect(
        PatientAge.fromDateOfBirth(
          DateTime(2027, 1, 1),
          asOf: DateTime(2026, 6, 15),
        ),
        isNull,
      );
    });
  });

  group('heart rate bands', () {
    test('a pulse of 140 is normal in an infant but critical in an adult', () {
      expect(
        VitalReference.heartRate(ageOf(months: 6)).classify(140),
        VitalFlag.normal,
      );
      expect(
        VitalReference.heartRate(ageOf(years: 40)).classify(140),
        VitalFlag.criticalHigh,
      );
    });

    test('a pulse of 70 is normal in an adult but critically low in an infant',
        () {
      expect(
        VitalReference.heartRate(ageOf(years: 40)).classify(70),
        VitalFlag.normal,
      );
      expect(
        VitalReference.heartRate(ageOf(months: 6)).classify(70),
        VitalFlag.criticalLow,
      );
    });

    test('falls back to adult ranges when age is unknown', () {
      expect(VitalReference.heartRate(null).classify(70), VitalFlag.normal);
      expect(VitalReference.heartRate(null).classify(140), VitalFlag.criticalHigh);
    });
  });

  group('systolic bands', () {
    test('uses 70 + 2 x age for the 1-10 year range', () {
      // A five-year-old's 5th centile is 70 + 10 = 80 mmHg.
      final range = VitalReference.systolic(ageOf(years: 5));
      expect(range.low, 80);
      expect(range.classify(79), VitalFlag.criticalLow);
      expect(range.classify(85), VitalFlag.normal);
    });

    test('flags a hypertensive crisis in an adult', () {
      final range = VitalReference.systolic(ageOf(years: 55));
      expect(range.classify(185), VitalFlag.criticalHigh);
      expect(range.classify(150), VitalFlag.high);
      expect(range.classify(115), VitalFlag.normal);
      expect(range.classify(88), VitalFlag.criticalLow);
    });
  });

  group('SpO2 and temperature', () {
    test('SpO2 below 90 is critical, 90-94 is low', () {
      expect(VitalReference.spo2.classify(89), VitalFlag.criticalLow);
      expect(VitalReference.spo2.classify(93), VitalFlag.low);
      expect(VitalReference.spo2.classify(97), VitalFlag.normal);
    });

    test('temperature extremes are critical', () {
      expect(VitalReference.temperature.classify(34.5), VitalFlag.criticalLow);
      expect(VitalReference.temperature.classify(38.4), VitalFlag.high);
      expect(VitalReference.temperature.classify(39.8), VitalFlag.criticalHigh);
      expect(VitalReference.temperature.classify(36.9), VitalFlag.normal);
    });
  });

  test('a missing value is unknown, never normal', () {
    expect(VitalReference.spo2.classify(null), VitalFlag.unknown);
    expect(VitalFlag.unknown.isAbnormal, isFalse);
    expect(VitalFlag.unknown.isCritical, isFalse);
  });
}
