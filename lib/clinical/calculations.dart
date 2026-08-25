import 'patient_age.dart';

/// Bedside calculations that clinicians would otherwise do on paper.
///
/// Every function returns null rather than guessing when an input is missing
/// or physiologically implausible — a wrong derived number on a chart is worse
/// than a blank.
abstract final class ClinicalCalc {
  /// Body mass index in kg/m². Guards against the classic unit slip of
  /// entering height in metres or weight in grams.
  static double? bmi({double? weightKg, double? heightCm}) {
    if (weightKg == null || heightCm == null) return null;
    if (weightKg <= 0 || weightKg > 500) return null;
    if (heightCm < 30 || heightCm > 260) return null;
    final metres = heightCm / 100;
    return weightKg / (metres * metres);
  }

  /// WHO adult classification. Deliberately not applied under 20 years, where
  /// BMI must be read against age-and-sex centiles instead.
  static String? bmiClass(double? bmi, PatientAge? age) {
    if (bmi == null) return null;
    if (age != null && age.years < 20) return 'Use paediatric centiles';
    if (bmi < 16) return 'Severe underweight';
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    if (bmi < 35) return 'Obese I';
    if (bmi < 40) return 'Obese II';
    return 'Obese III';
  }

  /// Mean arterial pressure ≈ DBP + (SBP − DBP)/3. Below ~65 mmHg organ
  /// perfusion is threatened, which is why it is worth surfacing next to BP.
  static double? meanArterialPressure({int? systolic, int? diastolic}) {
    if (systolic == null || diastolic == null) return null;
    if (systolic <= diastolic) return null;
    return diastolic + (systolic - diastolic) / 3;
  }

  static int? pulsePressure({int? systolic, int? diastolic}) {
    if (systolic == null || diastolic == null) return null;
    if (systolic <= diastolic) return null;
    return systolic - diastolic;
  }

  /// Shock index (HR ÷ SBP). Sustained values above ~0.9 in an adult flag
  /// occult haemodynamic compromise before hypotension appears.
  static double? shockIndex({int? heartRate, int? systolic}) {
    if (heartRate == null || systolic == null || systolic <= 0) return null;
    return heartRate / systolic;
  }

  /// ACC/AHA stage for an adult office reading. Staging requires repeated
  /// readings on separate occasions — this labels the single measurement only.
  static String? bloodPressureCategory({
    int? systolic,
    int? diastolic,
    PatientAge? age,
  }) {
    if (systolic == null || diastolic == null) return null;
    if (age != null && age.years < 18) return null;
    if (systolic >= 180 || diastolic >= 120) return 'Hypertensive crisis';
    if (systolic >= 140 || diastolic >= 90) return 'Stage 2 hypertension';
    if (systolic >= 130 || diastolic >= 80) return 'Stage 1 hypertension';
    if (systolic >= 120) return 'Elevated';
    if (systolic < 90 || diastolic < 60) return 'Hypotension';
    return 'Normal';
  }

  /// Fahrenheit entry is common on some devices; conversion lives here so the
  /// stored value is always Celsius.
  static double fahrenheitToCelsius(double f) => (f - 32) * 5 / 9;

  static double celsiusToFahrenheit(double c) => c * 9 / 5 + 32;

  static double mgDlToMmolGlucose(double mgDl) => mgDl / 18.0182;

  static double mmolToMgDlGlucose(double mmol) => mmol * 18.0182;

  /// Paediatric weight estimate (APLS) for when a child cannot be weighed.
  /// Explicitly an estimate — never use it in place of a real weight for
  /// drug dosing if a scale is available.
  static double? estimatedWeightKg(PatientAge? age) {
    if (age == null || age.years >= 12) return null;
    if (age.years < 1) return (age.totalMonths * 0.5) + 4;
    if (age.years <= 5) return 2.0 * (age.years + 4);
    return 4.0 * age.years;
  }
}
