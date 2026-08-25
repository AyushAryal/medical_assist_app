import 'dart:math' as math;

import '../explanations.dart';

/// One past appointment, reduced to what the estimators need.
class AppointmentOutcome {
  const AppointmentOutcome({
    required this.scheduledAt,
    required this.bookedAt,
    required this.attended,
    required this.wasCancelled,
    this.consultationMinutes,
    this.visitType,
  });

  final DateTime scheduledAt;
  final DateTime bookedAt;
  final bool attended;
  final bool wasCancelled;

  /// Door-to-door minutes, where the visit happened.
  final int? consultationMinutes;
  final String? visitType;

  /// A cancellation is not a no-show. Someone who calls to cancel is engaged
  /// with their care; someone who simply does not arrive is the one worth
  /// telephoning. Conflating them makes the estimate useless *and* unfair.
  bool get isNoShow => !attended && !wasCancelled;

  int get leadTimeDays =>
      scheduledAt.difference(bookedAt).inDays.clamp(0, 3650);
}

class NoShowRisk {
  const NoShowRisk({
    required this.probability,
    required this.band,
    required this.factors,
    required this.historyCount,
  });

  /// 0–1, an estimated rate, not a prediction about this person.
  final double probability;
  final NoShowBand band;
  final List<String> factors;
  final int historyCount;
}

enum NoShowBand { unknown, low, moderate, elevated }

extension NoShowBandX on NoShowBand {
  String get label => switch (this) {
        NoShowBand.unknown => 'No history',
        NoShowBand.low => 'Usually attends',
        NoShowBand.moderate => 'Sometimes misses',
        NoShowBand.elevated => 'Often misses',
      };
}

/// Estimates who is unlikely to arrive, so a reminder call goes to the right
/// person.
///
/// The ethical line here is firm and worth stating in code, because it is easy
/// to cross without noticing: **this is used to offer someone more support,
/// never less.** A high estimate justifies a reminder call or an earlier slot.
/// It must never be used to deprioritise a patient, to double-book over them,
/// or to refuse a booking. A missed appointment is usually a transport problem,
/// a work problem or a childcare problem, and treating it as unreliability is
/// both wrong and clinically counterproductive.
///
/// It is also deliberately built only from *this patient's own* history. No
/// demographic factor is used — not age, not sex, not district. A model that
/// learns which neighbourhoods miss appointments will reproduce whatever
/// inequality created that pattern and dress it up as arithmetic.
abstract final class NoShowEstimator {
  /// Below this many past appointments, no estimate is offered at all. Two
  /// appointments is not a pattern, and a "high risk" badge earned by missing
  /// one bus is worse than no badge.
  static const int minimumHistory = 4;

  static NoShowRisk estimate({
    required List<AppointmentOutcome> history,
    required DateTime scheduledFor,
    required DateTime bookedAt,
  }) {
    final past = history
        .where((a) => a.scheduledAt.isBefore(DateTime.now()))
        .toList();

    if (past.length < minimumHistory) {
      return NoShowRisk(
        probability: 0,
        band: NoShowBand.unknown,
        factors: <String>[
          'Only ${past.length} past appointment'
              '${past.length == 1 ? '' : 's'} on record — at least '
              '$minimumHistory are needed before this app will estimate.',
        ],
        historyCount: past.length,
      );
    }

    final factors = <String>[];

    // Base rate: how often this patient has missed, smoothed toward the
    // typical clinic rate so a run of four attendances does not read as an
    // impossible 0%.
    final missed = past.where((a) => a.isNoShow).length;
    const priorWeight = 3.0;
    const priorRate = 0.12;
    var probability =
        (missed + priorRate * priorWeight) / (past.length + priorWeight);
    factors.add(
      'Missed $missed of ${past.length} past appointments',
    );

    // Recency: behaviour six months ago says less than behaviour last month.
    final recent = past
        .where(
          (a) => a.scheduledAt
              .isAfter(DateTime.now().subtract(const Duration(days: 120))),
        )
        .toList();
    if (recent.length >= 2) {
      final recentMissed = recent.where((a) => a.isNoShow).length;
      final recentRate = recentMissed / recent.length;
      probability = probability * 0.55 + recentRate * 0.45;
      if (recentMissed > 0) {
        factors.add(
          'Missed $recentMissed of ${recent.length} in the last four months',
        );
      }
    }

    // Lead time: an appointment booked months ahead is more easily forgotten
    // and more likely to collide with something that came up since.
    final leadDays = scheduledFor.difference(bookedAt).inDays;
    if (leadDays > 42) {
      probability = math.min(1, probability + 0.07);
      factors.add('Booked $leadDays days ahead');
    } else if (leadDays <= 2) {
      probability = math.max(0, probability - 0.05);
      factors.add('Booked within the last two days');
    }

    final band = probability >= 0.35
        ? NoShowBand.elevated
        : probability >= 0.18
            ? NoShowBand.moderate
            : NoShowBand.low;

    return NoShowRisk(
      probability: probability.clamp(0.0, 1.0),
      band: band,
      factors: factors,
      historyCount: past.length,
    );
  }

  static MetricExplanation explain(NoShowRisk risk) {
    return MetricExplanation(
      title: 'Attendance — ${risk.band.label}',
      summary: risk.band == NoShowBand.unknown
          ? 'Not enough appointment history to say anything useful.'
          : 'An estimate of how often this patient has been unable to attend, '
              'so a reminder call can go where it will help most.',
      method: const <String>[
        "The patient's own past appointments are counted: how many were "
            'attended, and how many were missed without being cancelled.',
        'A cancellation is not counted as a miss. Someone who rings to cancel '
            'is engaged with their care.',
        'The rate is pulled toward a typical clinic average, so a short run of '
            'attendances does not read as a guarantee.',
        'Appointments in the last four months are weighted more heavily than '
            'older ones.',
        'An appointment booked a long way ahead is adjusted upward slightly; '
            'one booked in the last two days, downward.',
      ],
      derivation: <ExplainRow>[
        for (final factor in risk.factors) ExplainRow(label: factor, value: ''),
        if (risk.band != NoShowBand.unknown)
          ExplainRow(
            label: 'Estimated rate',
            value: '${(risk.probability * 100).round()}%',
          ),
      ],
      confidence: risk.band == NoShowBand.unknown
          ? ExplainConfidence.insufficientData
          : ExplainConfidence.heuristic,
      source: 'This app — from this patient’s own attendance history only',
      caveat: 'This is for offering support, not withholding it. It uses no '
          'age, sex, address or any other characteristic of the patient — only '
          'their own past appointments. Missing an appointment is usually a '
          'transport, work or childcare problem, and the right response to a '
          'high figure is a reminder call or a more convenient slot, never a '
          'lower priority.',
    );
  }
}

class WaitEstimate {
  const WaitEstimate({
    required this.wait,
    required this.aheadInQueue,
    required this.medianConsultation,
    required this.basedOnVisits,
  });

  final Duration wait;
  final int aheadInQueue;
  final Duration medianConsultation;

  /// How many past visits the median was taken from. Zero means the fallback
  /// was used and the figure should be presented as a default, not a
  /// measurement.
  final int basedOnVisits;

  bool get isMeasured => basedOnVisits >= WaitTimeEstimator.minimumVisits;
}

/// Tells a waiting patient roughly how long they have left.
///
/// The number is only as good as the clinic's own history, which is exactly
/// why it is computed from that history rather than from the booked slot
/// lengths — the booked length is what someone hoped, and the median is what
/// actually happens.
abstract final class WaitTimeEstimator {
  static const int minimumVisits = 5;

  /// Used until a clinic has enough of its own history.
  static const Duration defaultConsultation = Duration(minutes: 15);

  static WaitEstimate estimate({
    required int aheadInQueue,
    required List<AppointmentOutcome> completedVisits,
    String? visitType,
  }) {
    // Prefer the median for this type of visit; a procedure and a repeat
    // prescription are not the same appointment.
    var durations = completedVisits
        .where((v) => v.consultationMinutes != null)
        .where((v) => visitType == null || v.visitType == visitType)
        .map((v) => v.consultationMinutes!)
        .toList();

    if (durations.length < minimumVisits) {
      durations = completedVisits
          .where((v) => v.consultationMinutes != null)
          .map((v) => v.consultationMinutes!)
          .toList();
    }

    // Below the minimum, fall back to the default rather than treating one or
    // two consultations as typical. A median of a single visit is that visit,
    // which is exactly the noise the median exists to reject — and it would
    // contradict what the explanation sheet tells the user is happening.
    final median =
        durations.length < minimumVisits ? null : _median(durations);
    final consultation = median == null
        ? defaultConsultation
        : Duration(minutes: median.round());

    return WaitEstimate(
      wait: consultation * aheadInQueue,
      aheadInQueue: aheadInQueue,
      medianConsultation: consultation,
      basedOnVisits: durations.length,
    );
  }

  /// Median, not mean: one consultation that ran to ninety minutes because
  /// something went wrong should not shift every estimate for the rest of the
  /// day.
  static double? _median(List<int> values) {
    if (values.isEmpty) return null;
    final sorted = values.toList()..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle].toDouble()
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static MetricExplanation explain(WaitEstimate estimate) {
    return MetricExplanation(
      title: 'Estimated wait',
      summary: 'Roughly how long until this patient is called, based on how '
          'long consultations in this clinic actually take.',
      method: <String>[
        'The number of patients ahead in the queue is counted: '
            '${estimate.aheadInQueue}.',
        if (estimate.isMeasured)
          'The middle consultation length from the last '
              '${estimate.basedOnVisits} completed visits is taken — '
              '${estimate.medianConsultation.inMinutes} minutes. The middle '
              'value rather than the average, so one consultation that '
              'overran does not distort every estimate for the day.'
        else
          'There are not yet $minimumVisits completed visits to measure '
              'from, so a default of '
              '${defaultConsultation.inMinutes} minutes per consultation is '
              'used.',
        'The two are multiplied.',
      ],
      derivation: <ExplainRow>[
        ExplainRow(
          label: 'Patients ahead',
          value: '${estimate.aheadInQueue}',
        ),
        ExplainRow(
          label: 'Typical consultation',
          value: '${estimate.medianConsultation.inMinutes} min',
          note: estimate.isMeasured
              ? 'median of ${estimate.basedOnVisits} past visits'
              : 'default — not enough history yet',
        ),
      ],
      total: '${estimate.wait.inMinutes} minutes',
      confidence: estimate.isMeasured
          ? ExplainConfidence.heuristic
          : ExplainConfidence.insufficientData,
      source: 'This clinic’s own completed visits',
      caveat: 'It assumes the queue moves in order and that nothing urgent '
          'arrives. Both assumptions fail regularly — an emergency rightly '
          'takes precedence over everyone waiting.',
    );
  }
}
