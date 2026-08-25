/// Plausibility checks applied *while* a value is being typed.
///
/// These are not reference ranges — an abnormal vital sign is a clinical
/// finding and must always be recordable. These catch values that are not
/// physiologically possible and are therefore almost certainly a typing or
/// unit error: a respiratory rate of 160, a temperature of 3.7 °C, a weight of
/// 700 kg.
///
/// The distinction matters. Blocking an abnormal-but-real value would make the
/// software refuse to record the sickest patients. So an implausible value
/// produces a *warning*, never a hard block — the clinician can still override
/// it, and the record is never silently altered.
class FieldCheck {
  const FieldCheck._(this.message, this.isBlocking);

  const FieldCheck.warning(String message) : this._(message, false);
  const FieldCheck.error(String message) : this._(message, true);

  final String message;

  /// True only for values that cannot be stored at all (wrong format), never
  /// for values that are merely surprising.
  final bool isBlocking;

  static const FieldCheck? ok = null;
}

abstract final class ClinicalValidators {
  /// Widest values ever plausibly recorded, deliberately generous.
  static FieldCheck? heartRate(String? raw) => _range(
        raw,
        min: 20,
        max: 300,
        unit: 'bpm',
        hint: 'Check the reading — pulse is usually 40–180.',
      );

  static FieldCheck? respiratoryRate(String? raw) => _range(
        raw,
        min: 4,
        max: 80,
        unit: '/min',
        hint: 'Check the reading — respiratory rate is usually 8–40.',
      );

  static FieldCheck? spo2(String? raw) {
    final value = _parse(raw);
    if (value == null) return null;
    if (value > 100) {
      return const FieldCheck.error('Saturation cannot exceed 100%.');
    }
    if (value < 50) {
      return const FieldCheck.warning(
        'Below 50% is rarely compatible with life — check the probe.',
      );
    }
    return null;
  }

  /// Celsius. A value in the high 90s is almost certainly Fahrenheit, which is
  /// worth catching explicitly rather than storing as a lethal hyperthermia.
  static FieldCheck? temperatureC(String? raw) {
    final value = _parse(raw);
    if (value == null) return null;
    if (value >= 90 && value <= 110) {
      return const FieldCheck.warning(
        'That looks like Fahrenheit. This field expects °C.',
      );
    }
    if (value < 25 || value > 45) {
      return const FieldCheck.warning(
        'Outside 25–45 °C — check the reading.',
      );
    }
    return null;
  }

  static FieldCheck? systolic(String? raw) => _range(
        raw,
        min: 40,
        max: 300,
        unit: 'mmHg',
        hint: 'Check the reading — systolic is usually 70–200.',
      );

  static FieldCheck? diastolic(String? raw) => _range(
        raw,
        min: 20,
        max: 200,
        unit: 'mmHg',
        hint: 'Check the reading — diastolic is usually 40–120.',
      );

  /// A diastolic at or above the systolic is a transcription error, not a
  /// physiological state.
  static FieldCheck? bloodPressurePair(String? systolicRaw, String? diastolicRaw) {
    final s = _parse(systolicRaw);
    final d = _parse(diastolicRaw);
    if (s == null || d == null) return null;
    if (d >= s) {
      return const FieldCheck.warning(
        'Diastolic is not below systolic — values may be swapped.',
      );
    }
    return null;
  }

  static FieldCheck? weightKg(String? raw) {
    final value = _parse(raw);
    if (value == null) return null;
    if (value > 400) {
      return const FieldCheck.warning('Over 400 kg — was this entered in grams?');
    }
    if (value <= 0) return const FieldCheck.error('Weight must be positive.');
    return null;
  }

  /// Catches height entered in metres, the most common unit slip on this field.
  static FieldCheck? heightCm(String? raw) {
    final value = _parse(raw);
    if (value == null) return null;
    if (value > 0 && value < 30) {
      return const FieldCheck.warning(
        'That looks like metres. This field expects centimetres.',
      );
    }
    if (value > 260) {
      return const FieldCheck.warning('Over 260 cm — check the reading.');
    }
    return null;
  }

  static FieldCheck? glucoseMmol(String? raw) {
    final value = _parse(raw);
    if (value == null) return null;
    if (value > 40) {
      return const FieldCheck.warning(
        'Over 40 mmol/L — was this entered in mg/dL?',
      );
    }
    return null;
  }

  static FieldCheck? painScore(String? raw) => _range(
        raw,
        min: 0,
        max: 10,
        unit: '',
        hint: 'Pain is scored 0–10.',
      );

  /// Loose on purpose: phone formats vary by country and a partially entered
  /// number must not be flagged mid-typing.
  static FieldCheck? phone(String? raw) {
    final value = (raw ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
    if (value.isEmpty) return null;
    if (!RegExp(r'^\+?[0-9]+$').hasMatch(value)) {
      return const FieldCheck.error('Digits, spaces and + only.');
    }
    if (value.replaceAll('+', '').length < 6) {
      return const FieldCheck.warning('That looks too short for a phone number.');
    }
    return null;
  }

  static FieldCheck? requiredText(String? raw, String label) {
    if ((raw ?? '').trim().isEmpty) return FieldCheck.error('$label is required.');
    return null;
  }

  static double? _parse(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static FieldCheck? _range(
    String? raw, {
    required double min,
    required double max,
    required String unit,
    required String hint,
  }) {
    final value = _parse(raw);
    if (value == null) return null;
    if (value < min || value > max) return FieldCheck.warning(hint);
    return null;
  }
}
