import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/explanations.dart';
import 'package:medical_app/clinical/insights/schedule_insights.dart';

void main() {
  final now = DateTime(2026, 6, 1);

  AppointmentOutcome past({
    required int daysAgo,
    required bool attended,
    bool cancelled = false,
    int? minutes,
    String? type,
  }) {
    final at = now.subtract(Duration(days: daysAgo));
    return AppointmentOutcome(
      scheduledAt: at,
      bookedAt: at.subtract(const Duration(days: 7)),
      attended: attended,
      wasCancelled: cancelled,
      consultationMinutes: minutes,
      visitType: type,
    );
  }

  group('NoShowEstimator', () {
    test('offers no estimate below the minimum history', () {
      final risk = NoShowEstimator.estimate(
        history: <AppointmentOutcome>[
          past(daysAgo: 30, attended: false),
          past(daysAgo: 60, attended: true),
        ],
        scheduledFor: now.add(const Duration(days: 7)),
        bookedAt: now,
      );

      // Two appointments is not a pattern. A badge earned by missing one bus
      // is worse than no badge.
      expect(risk.band, NoShowBand.unknown);
      expect(risk.probability, 0);
    });

    test('a reliable attender reads as low', () {
      final risk = NoShowEstimator.estimate(
        history: <AppointmentOutcome>[
          for (var i = 1; i <= 8; i++) past(daysAgo: i * 30, attended: true),
        ],
        scheduledFor: now.add(const Duration(days: 7)),
        bookedAt: now,
      );

      expect(risk.band, NoShowBand.low);
      // Smoothed toward a clinic average, so a run of attendances never reads
      // as a guarantee.
      expect(risk.probability, greaterThan(0));
      expect(risk.probability, lessThan(0.18));
    });

    test('frequent recent misses read as elevated', () {
      final risk = NoShowEstimator.estimate(
        history: <AppointmentOutcome>[
          past(daysAgo: 10, attended: false),
          past(daysAgo: 40, attended: false),
          past(daysAgo: 70, attended: false),
          past(daysAgo: 100, attended: true),
          past(daysAgo: 130, attended: false),
          past(daysAgo: 160, attended: true),
        ],
        scheduledFor: now.add(const Duration(days: 7)),
        bookedAt: now,
      );

      expect(risk.band, NoShowBand.elevated);
    });

    test('a cancellation is not a no-show', () {
      List<AppointmentOutcome> history({required bool cancelled}) =>
          <AppointmentOutcome>[
            past(daysAgo: 10, attended: false, cancelled: cancelled),
            past(daysAgo: 40, attended: false, cancelled: cancelled),
            past(daysAgo: 70, attended: true),
            past(daysAgo: 100, attended: true),
            past(daysAgo: 130, attended: true),
          ];

      final cancelling = NoShowEstimator.estimate(
        history: history(cancelled: true),
        scheduledFor: now.add(const Duration(days: 7)),
        bookedAt: now,
      );
      final missing = NoShowEstimator.estimate(
        history: history(cancelled: false),
        scheduledFor: now.add(const Duration(days: 7)),
        bookedAt: now,
      );

      // Someone who rings to cancel is engaged with their care. Conflating the
      // two makes the estimate both useless and unfair.
      expect(cancelling.probability, lessThan(missing.probability));
      expect(cancelling.band, NoShowBand.low);
    });

    test('a long lead time raises the estimate slightly', () {
      final history = <AppointmentOutcome>[
        for (var i = 1; i <= 6; i++) past(daysAgo: i * 30, attended: true),
      ];

      final soon = NoShowEstimator.estimate(
        history: history,
        scheduledFor: now.add(const Duration(days: 1)),
        bookedAt: now,
      );
      final distant = NoShowEstimator.estimate(
        history: history,
        scheduledFor: now.add(const Duration(days: 90)),
        bookedAt: now,
      );

      expect(distant.probability, greaterThan(soon.probability));
    });

    test('the estimate is never certain in either direction', () {
      final never = NoShowEstimator.estimate(
        history: <AppointmentOutcome>[
          for (var i = 1; i <= 10; i++) past(daysAgo: i * 20, attended: false),
        ],
        scheduledFor: now.add(const Duration(days: 7)),
        bookedAt: now,
      );

      expect(never.probability, lessThan(1.0));
      expect(never.probability, greaterThan(0.0));
    });

    test('the explanation says what it must not be used for', () {
      final risk = NoShowEstimator.estimate(
        history: <AppointmentOutcome>[
          for (var i = 1; i <= 6; i++)
            past(daysAgo: i * 30, attended: i.isEven),
        ],
        scheduledFor: now.add(const Duration(days: 7)),
        bookedAt: now,
      );

      final explanation = NoShowEstimator.explain(risk);
      expect(explanation.confidence, ExplainConfidence.heuristic);
      // The ethical constraint is part of the feature, so it is asserted.
      expect(explanation.caveat, contains('not withholding'));
      expect(explanation.source, contains('own attendance history'));
    });
  });

  group('WaitTimeEstimator', () {
    test('falls back to a default before there is history to measure', () {
      final estimate = WaitTimeEstimator.estimate(
        aheadInQueue: 3,
        completedVisits: <AppointmentOutcome>[
          past(daysAgo: 0, attended: true, minutes: 20),
        ],
      );

      expect(estimate.isMeasured, isFalse);
      expect(
        estimate.medianConsultation,
        WaitTimeEstimator.defaultConsultation,
      );
      expect(estimate.wait, WaitTimeEstimator.defaultConsultation * 3);
    });

    test('uses the median of measured consultations', () {
      final estimate = WaitTimeEstimator.estimate(
        aheadInQueue: 2,
        completedVisits: <AppointmentOutcome>[
          past(daysAgo: 0, attended: true, minutes: 8),
          past(daysAgo: 0, attended: true, minutes: 10),
          past(daysAgo: 0, attended: true, minutes: 10),
          past(daysAgo: 0, attended: true, minutes: 12),
          past(daysAgo: 0, attended: true, minutes: 14),
        ],
      );

      expect(estimate.isMeasured, isTrue);
      expect(estimate.medianConsultation, const Duration(minutes: 10));
      expect(estimate.wait, const Duration(minutes: 20));
    });

    test('one overrunning consultation does not distort the day', () {
      // The reason for a median rather than a mean. The mean here is 32
      // minutes; the median is 10.
      final estimate = WaitTimeEstimator.estimate(
        aheadInQueue: 1,
        completedVisits: <AppointmentOutcome>[
          past(daysAgo: 0, attended: true, minutes: 9),
          past(daysAgo: 0, attended: true, minutes: 10),
          past(daysAgo: 0, attended: true, minutes: 10),
          past(daysAgo: 0, attended: true, minutes: 11),
          past(daysAgo: 0, attended: true, minutes: 120),
        ],
      );

      expect(estimate.medianConsultation, const Duration(minutes: 10));
    });

    test('prefers the median for the same kind of visit', () {
      final visits = <AppointmentOutcome>[
        for (var i = 0; i < 6; i++)
          past(daysAgo: 0, attended: true, minutes: 30, type: 'procedure'),
        for (var i = 0; i < 6; i++)
          past(daysAgo: 0, attended: true, minutes: 6, type: 'followUp'),
      ];

      expect(
        WaitTimeEstimator.estimate(
          aheadInQueue: 1,
          completedVisits: visits,
          visitType: 'procedure',
        ).medianConsultation,
        const Duration(minutes: 30),
      );
      expect(
        WaitTimeEstimator.estimate(
          aheadInQueue: 1,
          completedVisits: visits,
          visitType: 'followUp',
        ).medianConsultation,
        const Duration(minutes: 6),
      );
    });

    test('falls back to all visit types when one type is too sparse', () {
      final estimate = WaitTimeEstimator.estimate(
        aheadInQueue: 1,
        completedVisits: <AppointmentOutcome>[
          past(daysAgo: 0, attended: true, minutes: 12, type: 'followUp'),
          for (var i = 0; i < 6; i++)
            past(daysAgo: 0, attended: true, minutes: 12, type: 'newVisit'),
        ],
        visitType: 'procedure',
      );

      expect(estimate.isMeasured, isTrue);
      expect(estimate.medianConsultation, const Duration(minutes: 12));
    });

    test('nobody ahead means no wait', () {
      final estimate = WaitTimeEstimator.estimate(
        aheadInQueue: 0,
        completedVisits: const <AppointmentOutcome>[],
      );
      expect(estimate.wait, Duration.zero);
    });
  });
}
