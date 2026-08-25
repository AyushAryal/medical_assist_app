import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/validators.dart';

/// The critical property: warn on impossible values, never block plausible
/// ones. A form that refuses to record a dying patient's observations is worse
/// than one that accepts a typo.
void main() {
  group('never blocks abnormal-but-real values', () {
    test('accepts the extremes of survivable physiology without complaint', () {
      expect(ClinicalValidators.heartRate('180'), isNull);
      expect(ClinicalValidators.heartRate('35'), isNull);
      expect(ClinicalValidators.respiratoryRate('45'), isNull);
      expect(ClinicalValidators.systolic('75'), isNull);
      expect(ClinicalValidators.systolic('220'), isNull);
      expect(ClinicalValidators.temperatureC('41.5'), isNull);
      expect(ClinicalValidators.spo2('72'), isNull);
    });

    test('an out-of-range value warns but never blocks', () {
      final check = ClinicalValidators.heartRate('400');
      expect(check, isNotNull);
      expect(check!.isBlocking, isFalse);
    });
  });

  group('catches unit slips', () {
    test('Fahrenheit typed into a Celsius field', () {
      final check = ClinicalValidators.temperatureC('98.6');
      expect(check?.message, contains('Fahrenheit'));
      expect(check!.isBlocking, isFalse);
    });

    test('height typed in metres', () {
      expect(ClinicalValidators.heightCm('1.75')?.message, contains('metres'));
      expect(ClinicalValidators.heightCm('175'), isNull);
    });

    test('weight typed in grams', () {
      expect(ClinicalValidators.weightKg('70000')?.message, contains('grams'));
      expect(ClinicalValidators.weightKg('70'), isNull);
    });

    test('glucose typed in mg/dL', () {
      expect(ClinicalValidators.glucoseMmol('180')?.message, contains('mg/dL'));
      expect(ClinicalValidators.glucoseMmol('7.2'), isNull);
    });
  });

  group('impossible values', () {
    test('saturation above 100 is a hard error', () {
      final check = ClinicalValidators.spo2('105');
      expect(check, isNotNull);
      expect(check!.isBlocking, isTrue);
    });

    test('a swapped blood pressure pair is flagged', () {
      expect(ClinicalValidators.bloodPressurePair('80', '120'), isNotNull);
      expect(ClinicalValidators.bloodPressurePair('120', '80'), isNull);
    });

    test('pain outside 0-10 is flagged', () {
      expect(ClinicalValidators.painScore('11'), isNotNull);
      expect(ClinicalValidators.painScore('10'), isNull);
      expect(ClinicalValidators.painScore('0'), isNull);
    });
  });

  group('empty and partial input', () {
    test('never complains about an empty field', () {
      expect(ClinicalValidators.heartRate(''), isNull);
      expect(ClinicalValidators.heartRate(null), isNull);
      expect(ClinicalValidators.temperatureC(''), isNull);
      expect(ClinicalValidators.phone(''), isNull);
    });

    test('phone accepts international formats', () {
      expect(ClinicalValidators.phone('+977 9801234567'), isNull);
      expect(ClinicalValidators.phone('(020) 7946-0958'), isNull);
      expect(ClinicalValidators.phone('abc')?.isBlocking, isTrue);
    });
  });

  test('required text reports the field name', () {
    expect(
      ClinicalValidators.requiredText('  ', 'Given name')?.message,
      'Given name is required.',
    );
    expect(ClinicalValidators.requiredText('Asha', 'Given name'), isNull);
  });
}
