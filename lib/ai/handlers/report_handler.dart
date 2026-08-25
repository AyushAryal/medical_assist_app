import '../../clinical/explanations.dart';
import '../cohort/cohort_query.dart';
import '../../data/repositories/clinical_repository.dart';
import '../../core/utils/formatters.dart';
import '../analytics/analysis.dart';
import '../intent.dart';
import '../presentation.dart';
import '../provenance.dart';

/// Answers "how is this distributed" rather than "who".
///
/// A separate handler because it is a separate question, and conflating them
/// is how reporting features end up unread: a clinic manager asking for
/// activity by month does not want a list of 300 visits, and a clinician
/// asking who is on warfarin does not want a bar chart.
///
/// Every breakdown here is one query per bucket rather than a `GROUP BY`. On a
/// register of this size that is a handful of counting queries against indexed
/// columns, and it buys something worth more than the microseconds: each
/// bucket is the *same* hand-written, tested WHERE clause the rest of the app
/// uses, so a cohort and its bar can never disagree about who is in it.
class ReportHandler {
  const ReportHandler(this._repository);

  final ClinicalRepository _repository;

  Future<Presentation> run(
    ReportIntent intent,
    Provenance provenance, {
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();

    final bars = switch (intent.kind) {
      ReportKind.activityOverTime => await _overTime(intent.query, now),
      ReportKind.byAgeBand => await _byAgeBand(intent.query),
      ReportKind.bySex => await _bySex(intent.query),
      ReportKind.byVisitType => await _byVisitType(intent.query),
      ReportKind.byStatus => await _byStatus(intent.query),
    };

    provenance.add(
      'execute',
      'Counted ${bars.length} buckets',
      detail: 'Each bucket is the same tested filter the rest of the app '
          'uses, so a bar and a list can never disagree.',
    );

    final total = bars.fold<int>(0, (sum, bar) => sum + bar.value);

    return ChartPresentation(
      style: intent.kind == ReportKind.activityOverTime
          ? ChartStyle.area
          : (bars.length <= 6 ? ChartStyle.donut : ChartStyle.bar),
      points: <ChartPoint>[
        for (final bar in bars)
          ChartPoint(label: bar.label, value: bar.value.toDouble(), n: bar.value),
      ],
      headline: total == 0
          ? 'Nothing to chart for that.'
          : '$total across ${bars.length} '
              '${bars.length == 1 ? 'group' : 'groups'}.',
      caption: intent.kind.label,
      explanation: MetricExplanation(
        title: intent.kind.label,
        summary: 'Each bar is a separate count using the same filters shown '
            'below.',
        method: <String>[
          'The buckets are counted one at a time with the same tested query '
              'the rest of the app uses, so a bar and the list behind it can '
              'never disagree about who is in it.',
          'Bars are scaled to the largest, so the shape shows relative size '
              'rather than an absolute count.',
          if (intent.kind == ReportKind.activityOverTime)
            'The most recent bucket is still filling, so it will almost always '
                'look short.',
          if (intent.kind == ReportKind.byAgeBand)
            'A patient with no recorded date of birth cannot be placed in an '
                'age band and is left out of every one.',
        ],
        derivation: <ExplainRow>[
          for (final bar in bars)
            ExplainRow(label: bar.label, value: '${bar.value}'),
        ],
        total: '$total',
        confidence: ExplainConfidence.measured,
        caveat: 'It counts what is recorded, not what happened. A quiet week '
            'in the chart may be a quiet week, or a week when nobody had time '
            'to write things down.',
      ),
    );
  }

  Future<List<({String label, int value})>> _overTime(
    CohortQuery query,
    DateTime now,
  ) async {
    // Twelve weeks: long enough to see a shape, short enough that each bar is
    // still a period someone remembers.
    final out = <({String label, int value})>[];
    for (var offset = 11; offset >= 0; offset--) {
      final end = now.subtract(Duration(days: offset * 7));
      final start = end.subtract(const Duration(days: 7));
      final bucket = query.copyWith(periodFrom: start, periodTo: end);
      out.add((
        label: Fmt.dateShort(start),
        value: await _count(bucket),
      ));
    }
    return out;
  }

  Future<List<({String label, int value})>> _byAgeBand(
    CohortQuery query,
  ) async {
    final out = <({String label, int value})>[];
    for (final band in AgeBand.values) {
      // `under1` is inside `under5`, so showing both double-counts the
      // youngest children in what reads as a partition.
      if (band == AgeBand.under1) continue;
      out.add((
        label: band.label,
        value: await _count(query.copyWith(ageBand: band)),
      ));
    }
    return out;
  }

  Future<List<({String label, int value})>> _bySex(CohortQuery query) async {
    final out = <({String label, int value})>[];
    for (final sex in <String>['female', 'male', 'intersex', 'unknown']) {
      final value = await _count(query.copyWith(sexAtBirth: sex));
      if (value > 0 || sex != 'intersex') {
        out.add((label: _sentence(sex), value: value));
      }
    }
    return out;
  }

  Future<List<({String label, int value})>> _byVisitType(
    CohortQuery query,
  ) async {
    const types = <String>[
      'newVisit', 'followUp', 'emergency', 'procedure', 'antenatal',
    ];
    return <({String label, int value})>[
      for (final type in types)
        (
          label: _sentence(type),
          value: await _count(query.copyWith(visitType: type)),
        ),
    ];
  }

  Future<List<({String label, int value})>> _byStatus(
    CohortQuery query,
  ) async {
    const statuses = <String>[
      'scheduled', 'arrived', 'completed', 'noShow', 'cancelled',
    ];
    return <({String label, int value})>[
      for (final status in statuses)
        (
          label: _sentence(status),
          value: await _count(
            query.copyWith(
              entity: QueryEntity.appointments,
              appointmentStatus: status,
            ),
          ),
        ),
    ];
  }

  Future<int> _count(CohortQuery query) => switch (query.entity) {
        QueryEntity.appointments =>
          _repository.cohorts.appointmentCount(query),
        QueryEntity.visits => _repository.cohorts.encounterCount(query),
        QueryEntity.vitals => _repository.cohorts.vitalsCount(query),
        QueryEntity.notes => _repository.cohorts.noteCount(query),
        QueryEntity.files => _repository.cohorts.fileCount(query),
        QueryEntity.patients => _repository.cohorts.count(query),
      };

  /// `noShow` → `No show`. Enum names are for code; a chart axis is read by a
  /// person.
  static String _sentence(String camel) {
    final spaced = camel.replaceAllMapped(
      RegExp(r'(?<=[a-z])([A-Z])'),
      (match) => ' ${match.group(1)!.toLowerCase()}',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}
