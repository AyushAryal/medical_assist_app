/// NEWS2 — the Royal College of Physicians' National Early Warning Score 2.
///
/// Scope and safety, verbatim from the standard's own guidance:
///
/// * Validated for **acutely ill adults aged 16 and over**.
/// * **Not** validated in pregnancy, and **not** for children — both have
///   physiology that makes the adult bands misleading. [News2Calculator]
///   refuses to score those patients rather than returning a number the UI
///   might display.
/// * It is a **track-and-trigger aid**, not a diagnosis. Escalation is always
///   a clinical decision; the score never overrides concern about a patient
///   who looks unwell.
///
/// SpO2 Scale 2 (target 88–92% in chronic hypercapnic respiratory failure)
/// must be prescribed by a clinician per patient, so it is opt-in via
/// [News2Input.useSpo2Scale2].
library;

enum Consciousness { alert, confusion, voice, pain, unresponsive }

extension ConsciousnessX on Consciousness {
  /// The ACVPU letter used on observation charts.
  String get code => switch (this) {
        Consciousness.alert => 'A',
        Consciousness.confusion => 'C',
        Consciousness.voice => 'V',
        Consciousness.pain => 'P',
        Consciousness.unresponsive => 'U',
      };

  String get label => switch (this) {
        Consciousness.alert => 'Alert',
        Consciousness.confusion => 'New confusion',
        Consciousness.voice => 'Responds to voice',
        Consciousness.pain => 'Responds to pain',
        Consciousness.unresponsive => 'Unresponsive',
      };

  /// New confusion/delirium scores the same as V, P and U in NEWS2.
  bool get isAlert => this == Consciousness.alert;

  static Consciousness? parse(String? value) {
    if (value == null) return null;
    return Consciousness.values
        .where((c) => c.name == value || c.code == value)
        .firstOrNull;
  }
}

enum News2Risk { low, lowMedium, medium, high }

extension News2RiskX on News2Risk {
  String get label => switch (this) {
        News2Risk.low => 'Low',
        News2Risk.lowMedium => 'Low–medium',
        News2Risk.medium => 'Medium',
        News2Risk.high => 'High',
      };

  /// Response guidance as published with NEWS2. Local escalation policy always
  /// takes precedence, which is why this is phrased as guidance.
  String get response => switch (this) {
        News2Risk.low =>
          'Continue routine observations, minimum 12-hourly.',
        News2Risk.lowMedium =>
          'Registered nurse to review; minimum 1-hourly observations.',
        News2Risk.medium =>
          'Urgent review by a clinician competent in acute illness; '
              'minimum 1-hourly observations.',
        News2Risk.high =>
          'Emergency assessment by a critical-care-capable team; '
              'continuous monitoring.',
      };
}

class News2Input {
  const News2Input({
    this.respiratoryRate,
    this.spo2,
    this.onOxygen = false,
    this.systolicBp,
    this.heartRate,
    this.consciousness,
    this.temperatureC,
    this.useSpo2Scale2 = false,
  });

  final int? respiratoryRate;
  final int? spo2;
  final bool onOxygen;
  final int? systolicBp;
  final int? heartRate;
  final Consciousness? consciousness;
  final double? temperatureC;
  final bool useSpo2Scale2;
}

/// Why a score could not be produced. Displayed to the user instead of a
/// number, so nobody mistakes "we didn't score this" for "the score is 0".
enum News2Unavailable { ageOutOfScope, pregnancy, incompleteObservations }

class News2Result {
  const News2Result({
    required this.total,
    required this.risk,
    required this.parameterScores,
    required this.hasSingleParameterThree,
    required this.algorithmVersion,
  });

  final int total;
  final News2Risk risk;

  /// Per-parameter breakdown, so the clinician can see *what* drove the score
  /// rather than being handed an opaque total.
  final Map<String, int> parameterScores;

  /// A single parameter scoring 3 triggers escalation on its own, even when
  /// the aggregate is otherwise low.
  final bool hasSingleParameterThree;

  final String algorithmVersion;
}

abstract final class News2Calculator {
  /// Stored alongside every score so a historic record keeps the meaning it
  /// had when it was taken, even if this file is later revised.
  static const String algorithmVersion = 'NEWS2-RCP-2017';

  /// All seven parameters are required. A partial NEWS2 is not a NEWS2 —
  /// omitting an unrecorded parameter silently under-scores a sick patient.
  static const List<String> requiredParameters = <String>[
    'respiratoryRate',
    'spo2',
    'systolicBp',
    'heartRate',
    'consciousness',
    'temperatureC',
  ];

  static News2Unavailable? unavailableReason({
    required int? ageYears,
    required bool isPregnant,
    required News2Input input,
  }) {
    if (ageYears == null || ageYears < 16) return News2Unavailable.ageOutOfScope;
    if (isPregnant) return News2Unavailable.pregnancy;
    if (missingParameters(input).isNotEmpty) {
      return News2Unavailable.incompleteObservations;
    }
    return null;
  }

  static List<String> missingParameters(News2Input input) {
    return <String>[
      if (input.respiratoryRate == null) 'respiratoryRate',
      if (input.spo2 == null) 'spo2',
      if (input.systolicBp == null) 'systolicBp',
      if (input.heartRate == null) 'heartRate',
      if (input.consciousness == null) 'consciousness',
      if (input.temperatureC == null) 'temperatureC',
    ];
  }

  /// Returns null when the patient or the observation set is out of scope.
  static News2Result? score({
    required int? ageYears,
    required bool isPregnant,
    required News2Input input,
  }) {
    if (unavailableReason(
          ageYears: ageYears,
          isPregnant: isPregnant,
          input: input,
        ) !=
        null) {
      return null;
    }

    final scores = <String, int>{
      'Respiration rate': _respirationScore(input.respiratoryRate!),
      'SpO₂': input.useSpo2Scale2
          ? _spo2Scale2Score(input.spo2!, input.onOxygen)
          : _spo2Scale1Score(input.spo2!),
      'Air or oxygen': input.onOxygen ? 2 : 0,
      'Systolic BP': _systolicScore(input.systolicBp!),
      'Pulse': _pulseScore(input.heartRate!),
      'Consciousness': input.consciousness!.isAlert ? 0 : 3,
      'Temperature': _temperatureScore(input.temperatureC!),
    };

    final total = scores.values.fold<int>(0, (sum, v) => sum + v);
    final hasThree = scores.values.any((v) => v >= 3);

    return News2Result(
      total: total,
      risk: _risk(total, hasThree),
      parameterScores: scores,
      hasSingleParameterThree: hasThree,
      algorithmVersion: algorithmVersion,
    );
  }

  static News2Risk _risk(int total, bool hasThree) {
    if (total >= 7) return News2Risk.high;
    if (total >= 5) return News2Risk.medium;
    if (hasThree) return News2Risk.lowMedium;
    return News2Risk.low;
  }

  static int _respirationScore(int rr) {
    if (rr <= 8) return 3;
    if (rr <= 11) return 1;
    if (rr <= 20) return 0;
    if (rr <= 24) return 2;
    return 3;
  }

  static int _spo2Scale1Score(int spo2) {
    if (spo2 <= 91) return 3;
    if (spo2 <= 93) return 2;
    if (spo2 <= 95) return 1;
    return 0;
  }

  /// Scale 2 targets 88–92%: a *high* saturation on oxygen is itself a risk in
  /// hypercapnic respiratory failure, so the band is non-monotonic.
  static int _spo2Scale2Score(int spo2, bool onOxygen) {
    if (spo2 <= 83) return 3;
    if (spo2 <= 85) return 2;
    if (spo2 <= 87) return 1;
    if (spo2 <= 92) return 0;
    if (!onOxygen) return 0;
    if (spo2 <= 94) return 1;
    if (spo2 <= 96) return 2;
    return 3;
  }

  static int _systolicScore(int sbp) {
    if (sbp <= 90) return 3;
    if (sbp <= 100) return 2;
    if (sbp <= 110) return 1;
    if (sbp <= 219) return 0;
    return 3;
  }

  static int _pulseScore(int hr) {
    if (hr <= 40) return 3;
    if (hr <= 50) return 1;
    if (hr <= 90) return 0;
    if (hr <= 110) return 1;
    if (hr <= 130) return 2;
    return 3;
  }

  static int _temperatureScore(double t) {
    if (t <= 35.0) return 3;
    if (t <= 36.0) return 1;
    if (t <= 38.0) return 0;
    if (t <= 39.0) return 1;
    return 2;
  }
}
