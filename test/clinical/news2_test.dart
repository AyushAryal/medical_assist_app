import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/news2.dart';

/// NEWS2 drives escalation decisions, so every band boundary is pinned here.
/// If a threshold in `news2.dart` is ever changed, these fail loudly rather
/// than silently altering how sick a patient appears.
void main() {
  News2Result scoreOf(News2Input input) => News2Calculator.score(
        ageYears: 40,
        isPregnant: false,
        input: input,
      )!;

  const healthy = News2Input(
    respiratoryRate: 16,
    spo2: 98,
    onOxygen: false,
    systolicBp: 120,
    heartRate: 70,
    consciousness: Consciousness.alert,
    temperatureC: 36.8,
  );

  group('scope', () {
    test('refuses to score children', () {
      expect(
        News2Calculator.score(
          ageYears: 10,
          isPregnant: false,
          input: healthy,
        ),
        isNull,
      );
      expect(
        News2Calculator.unavailableReason(
          ageYears: 10,
          isPregnant: false,
          input: healthy,
        ),
        News2Unavailable.ageOutOfScope,
      );
    });

    test('refuses to score in pregnancy', () {
      expect(
        News2Calculator.score(
          ageYears: 28,
          isPregnant: true,
          input: healthy,
        ),
        isNull,
      );
    });

    test('refuses to score an incomplete observation set', () {
      const partial = News2Input(respiratoryRate: 16, spo2: 98);
      expect(
        News2Calculator.unavailableReason(
          ageYears: 40,
          isPregnant: false,
          input: partial,
        ),
        News2Unavailable.incompleteObservations,
      );
      expect(News2Calculator.missingParameters(partial), hasLength(4));
    });

    test('16 is in scope, 15 is not', () {
      expect(
        News2Calculator.score(ageYears: 16, isPregnant: false, input: healthy),
        isNotNull,
      );
      expect(
        News2Calculator.score(ageYears: 15, isPregnant: false, input: healthy),
        isNull,
      );
    });
  });

  group('aggregate scoring', () {
    test('a well patient scores zero and is low risk', () {
      final result = scoreOf(healthy);
      expect(result.total, 0);
      expect(result.risk, News2Risk.low);
      expect(result.hasSingleParameterThree, isFalse);
    });

    test('supplemental oxygen alone adds 2', () {
      // SpO2 98 on oxygen: 0 for saturation on Scale 1, +2 for being on O2.
      final result = scoreOf(const News2Input(
        respiratoryRate: 16,
        spo2: 98,
        onOxygen: true,
        systolicBp: 120,
        heartRate: 70,
        consciousness: Consciousness.alert,
        temperatureC: 36.8,
      ));
      expect(result.total, 2);
      expect(result.parameterScores['Air or oxygen'], 2);
    });

    test('new confusion scores 3 like V, P and U', () {
      for (final level in <Consciousness>[
        Consciousness.confusion,
        Consciousness.voice,
        Consciousness.pain,
        Consciousness.unresponsive,
      ]) {
        final result = scoreOf(const News2Input(
          respiratoryRate: 16,
          spo2: 98,
          systolicBp: 120,
          heartRate: 70,
          temperatureC: 36.8,
        ).copyWithConsciousness(level));
        expect(result.parameterScores['Consciousness'], 3, reason: level.name);
      }
    });

    test('a deteriorating septic patient reaches high risk', () {
      // RR 26 (+3), SpO2 91 (+3), on O2 (+2), SBP 88 (+3), HR 125 (+2),
      // alert (0), 39.4 C (+2) = 15.
      final result = scoreOf(const News2Input(
        respiratoryRate: 26,
        spo2: 91,
        onOxygen: true,
        systolicBp: 88,
        heartRate: 125,
        consciousness: Consciousness.alert,
        temperatureC: 39.4,
      ));
      expect(result.total, 15);
      expect(result.risk, News2Risk.high);
    });
  });

  group('risk banding', () {
    test('a single parameter scoring 3 lifts a low total to low-medium', () {
      // RR 7 scores 3; everything else is normal, so the total is only 3.
      final result = scoreOf(const News2Input(
        respiratoryRate: 7,
        spo2: 98,
        systolicBp: 120,
        heartRate: 70,
        consciousness: Consciousness.alert,
        temperatureC: 36.8,
      ));
      expect(result.total, 3);
      expect(result.hasSingleParameterThree, isTrue);
      expect(result.risk, News2Risk.lowMedium);
    });

    test('totals of 5 and 6 are medium risk', () {
      // RR 22 (+2), SpO2 92 (+2), HR 95 (+1) = 5.
      final medium = scoreOf(const News2Input(
        respiratoryRate: 22,
        spo2: 92,
        systolicBp: 120,
        heartRate: 95,
        consciousness: Consciousness.alert,
        temperatureC: 36.8,
      ));
      expect(medium.total, 5);
      expect(medium.risk, News2Risk.medium);
    });

    test('7 and above is high risk', () {
      // RR 22 (+2), SpO2 92 (+2), HR 115 (+2), temp 38.5 (+1) = 7.
      final high = scoreOf(const News2Input(
        respiratoryRate: 22,
        spo2: 92,
        systolicBp: 120,
        heartRate: 115,
        consciousness: Consciousness.alert,
        temperatureC: 38.5,
      ));
      expect(high.total, 7);
      expect(high.risk, News2Risk.high);
    });
  });

  group('parameter boundaries', () {
    void expectScore(String parameter, News2Input input, int expected) {
      expect(scoreOf(input).parameterScores[parameter], expected);
    }

    test('respiration rate bands', () {
      const cases = <int, int>{8: 3, 9: 1, 11: 1, 12: 0, 20: 0, 21: 2, 24: 2, 25: 3};
      cases.forEach((rr, expected) {
        expectScore(
          'Respiration rate',
          News2Input(
            respiratoryRate: rr,
            spo2: 98,
            systolicBp: 120,
            heartRate: 70,
            consciousness: Consciousness.alert,
            temperatureC: 36.8,
          ),
          expected,
        );
      });
    });

    test('systolic bands', () {
      const cases = <int, int>{
        90: 3, 91: 2, 100: 2, 101: 1, 110: 1, 111: 0, 219: 0, 220: 3,
      };
      cases.forEach((sbp, expected) {
        expectScore(
          'Systolic BP',
          News2Input(
            respiratoryRate: 16,
            spo2: 98,
            systolicBp: sbp,
            heartRate: 70,
            consciousness: Consciousness.alert,
            temperatureC: 36.8,
          ),
          expected,
        );
      });
    });

    test('pulse bands', () {
      const cases = <int, int>{
        40: 3, 41: 1, 50: 1, 51: 0, 90: 0, 91: 1, 110: 1, 111: 2, 130: 2, 131: 3,
      };
      cases.forEach((hr, expected) {
        expectScore(
          'Pulse',
          News2Input(
            respiratoryRate: 16,
            spo2: 98,
            systolicBp: 120,
            heartRate: hr,
            consciousness: Consciousness.alert,
            temperatureC: 36.8,
          ),
          expected,
        );
      });
    });

    test('temperature bands', () {
      // A list of pairs rather than a map: doubles have no primitive equality
      // and so cannot be constant map keys.
      const cases = <(double, int)>[
        (35.0, 3), (35.1, 1), (36.0, 1), (36.1, 0),
        (38.0, 0), (38.1, 1), (39.0, 1), (39.1, 2),
      ];
      for (final (temp, expected) in cases) {
        expectScore(
          'Temperature',
          News2Input(
            respiratoryRate: 16,
            spo2: 98,
            systolicBp: 120,
            heartRate: 70,
            consciousness: Consciousness.alert,
            temperatureC: temp,
          ),
          expected,
        );
      }
    });

    test('SpO2 Scale 1 bands', () {
      const cases = <int, int>{91: 3, 92: 2, 93: 2, 94: 1, 95: 1, 96: 0, 100: 0};
      cases.forEach((spo2, expected) {
        expectScore(
          'SpO₂',
          News2Input(
            respiratoryRate: 16,
            spo2: spo2,
            systolicBp: 120,
            heartRate: 70,
            consciousness: Consciousness.alert,
            temperatureC: 36.8,
          ),
          expected,
        );
      });
    });

    test('SpO2 Scale 2 penalises high saturation on oxygen', () {
      // 88-92% is the target range in hypercapnic respiratory failure, so a
      // saturation of 97% *on oxygen* is itself a risk and scores 3.
      final onTarget = News2Calculator.score(
        ageYears: 70,
        isPregnant: false,
        input: const News2Input(
          respiratoryRate: 16,
          spo2: 90,
          onOxygen: true,
          systolicBp: 120,
          heartRate: 70,
          consciousness: Consciousness.alert,
          temperatureC: 36.8,
          useSpo2Scale2: true,
        ),
      )!;
      expect(onTarget.parameterScores['SpO₂'], 0);

      final overOxygenated = News2Calculator.score(
        ageYears: 70,
        isPregnant: false,
        input: const News2Input(
          respiratoryRate: 16,
          spo2: 97,
          onOxygen: true,
          systolicBp: 120,
          heartRate: 70,
          consciousness: Consciousness.alert,
          temperatureC: 36.8,
          useSpo2Scale2: true,
        ),
      )!;
      expect(overOxygenated.parameterScores['SpO₂'], 3);
    });
  });

  test('algorithm version is stamped on every result', () {
    expect(scoreOf(healthy).algorithmVersion, 'NEWS2-RCP-2017');
  });
}

extension on News2Input {
  News2Input copyWithConsciousness(Consciousness level) => News2Input(
        respiratoryRate: respiratoryRate,
        spo2: spo2,
        onOxygen: onOxygen,
        systolicBp: systolicBp,
        heartRate: heartRate,
        consciousness: level,
        temperatureC: temperatureC,
        useSpo2Scale2: useSpo2Scale2,
      );
}
