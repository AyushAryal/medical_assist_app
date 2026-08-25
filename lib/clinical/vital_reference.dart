import 'patient_age.dart';

/// How a single measurement sits against its reference range.
enum VitalFlag { unknown, criticalLow, low, normal, high, criticalHigh }

extension VitalFlagX on VitalFlag {
  bool get isAbnormal => this != VitalFlag.normal && this != VitalFlag.unknown;
  bool get isCritical =>
      this == VitalFlag.criticalLow || this == VitalFlag.criticalHigh;

  String get label => switch (this) {
        VitalFlag.criticalLow => 'Critically low',
        VitalFlag.low => 'Low',
        VitalFlag.normal => 'Normal',
        VitalFlag.high => 'High',
        VitalFlag.criticalHigh => 'Critically high',
        VitalFlag.unknown => '',
      };

  String get shortLabel => switch (this) {
        VitalFlag.criticalLow => 'LL',
        VitalFlag.low => 'L',
        VitalFlag.normal => '',
        VitalFlag.high => 'H',
        VitalFlag.criticalHigh => 'HH',
        VitalFlag.unknown => '',
      };
}

/// A reference band. `criticalLow`/`criticalHigh` are the escalation
/// thresholds, not merely "very abnormal" — crossing one is what the UI
/// surfaces in red.
class VitalRange {
  const VitalRange({
    required this.low,
    required this.high,
    this.criticalLow,
    this.criticalHigh,
  });

  final double low;
  final double high;
  final double? criticalLow;
  final double? criticalHigh;

  VitalFlag classify(num? value) {
    if (value == null) return VitalFlag.unknown;
    final v = value.toDouble();
    if (criticalLow != null && v <= criticalLow!) return VitalFlag.criticalLow;
    if (criticalHigh != null && v >= criticalHigh!) {
      return VitalFlag.criticalHigh;
    }
    if (v < low) return VitalFlag.low;
    if (v > high) return VitalFlag.high;
    return VitalFlag.normal;
  }

  String get display {
    final l = low == low.roundToDouble() ? low.toStringAsFixed(0) : '$low';
    final h = high == high.roundToDouble() ? high.toStringAsFixed(0) : '$high';
    return '$l–$h';
  }
}

/// Age-banded reference ranges.
///
/// Paediatric heart and respiratory rates are drawn from the widely taught
/// APLS/PALS age bands. These are decision *support* only: they are population
/// ranges, they assume an afebrile resting child, and a value inside the band
/// never overrides the clinician in front of the patient.
abstract final class VitalReference {
  static VitalRange heartRate(PatientAge? age) {
    if (age == null) {
      return const VitalRange(
        low: 60,
        high: 100,
        criticalLow: 40,
        criticalHigh: 130,
      );
    }
    if (age.years < 1) {
      return const VitalRange(
        low: 110,
        high: 160,
        criticalLow: 90,
        criticalHigh: 180,
      );
    }
    if (age.years < 2) {
      return const VitalRange(
        low: 100,
        high: 150,
        criticalLow: 80,
        criticalHigh: 170,
      );
    }
    if (age.years < 5) {
      return const VitalRange(
        low: 95,
        high: 140,
        criticalLow: 70,
        criticalHigh: 160,
      );
    }
    if (age.years < 12) {
      return const VitalRange(
        low: 80,
        high: 120,
        criticalLow: 60,
        criticalHigh: 140,
      );
    }
    return const VitalRange(
      low: 60,
      high: 100,
      criticalLow: 40,
      criticalHigh: 130,
    );
  }

  static VitalRange respiratoryRate(PatientAge? age) {
    if (age == null) {
      return const VitalRange(
        low: 12,
        high: 20,
        criticalLow: 8,
        criticalHigh: 25,
      );
    }
    if (age.years < 1) {
      return const VitalRange(
        low: 30,
        high: 40,
        criticalLow: 20,
        criticalHigh: 60,
      );
    }
    if (age.years < 2) {
      return const VitalRange(
        low: 25,
        high: 35,
        criticalLow: 20,
        criticalHigh: 50,
      );
    }
    if (age.years < 5) {
      return const VitalRange(
        low: 25,
        high: 30,
        criticalLow: 18,
        criticalHigh: 45,
      );
    }
    if (age.years < 12) {
      return const VitalRange(
        low: 20,
        high: 25,
        criticalLow: 14,
        criticalHigh: 35,
      );
    }
    return const VitalRange(
      low: 12,
      high: 20,
      criticalLow: 8,
      criticalHigh: 25,
    );
  }

  /// Systolic lower limit below one year is a flat 70 mmHg; from 1–10 years
  /// the 5th-centile approximation `70 + 2 × age` is used; adolescents and
  /// adults use 90.
  static VitalRange systolic(PatientAge? age) {
    if (age == null || age.years >= 16) {
      return const VitalRange(
        low: 90,
        high: 139,
        criticalLow: 90,
        criticalHigh: 180,
      );
    }
    if (age.years < 1) {
      return const VitalRange(
        low: 70,
        high: 100,
        criticalLow: 70,
        criticalHigh: 110,
      );
    }
    if (age.years <= 10) {
      final low = 70 + 2 * age.years;
      return VitalRange(
        low: low.toDouble(),
        high: low + 40,
        criticalLow: low.toDouble(),
        criticalHigh: low + 50,
      );
    }
    return const VitalRange(
      low: 90,
      high: 130,
      criticalLow: 90,
      criticalHigh: 160,
    );
  }

  static VitalRange diastolic(PatientAge? age) {
    if (age == null || age.years >= 16) {
      return const VitalRange(
        low: 60,
        high: 89,
        criticalLow: 40,
        criticalHigh: 120,
      );
    }
    return const VitalRange(low: 40, high: 80, criticalLow: 30, criticalHigh: 100);
  }

  /// SpO2 on room air at sea level. Patients with chronic hypercapnic
  /// respiratory failure have a lower target (88–92%) — that override belongs
  /// on the patient record, not in a global constant.
  static const VitalRange spo2 = VitalRange(
    low: 95,
    high: 100,
    criticalLow: 90,
  );

  static const VitalRange temperature = VitalRange(
    low: 36.1,
    high: 37.9,
    criticalLow: 35.0,
    criticalHigh: 39.5,
  );

  static const VitalRange bloodGlucoseMmol = VitalRange(
    low: 4.0,
    high: 7.8,
    criticalLow: 3.0,
    criticalHigh: 20.0,
  );

  static const VitalRange painScore = VitalRange(low: 0, high: 3, criticalHigh: 8);

  static const VitalRange capillaryRefillSec =
      VitalRange(low: 0, high: 2, criticalHigh: 4);
}
