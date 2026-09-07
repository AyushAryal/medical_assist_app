import '../flags/clinical_flag.dart';
import '../news2.dart';
import 'record_summary.dart';

/// Whether allergies have been asked about, and the answer.
///
/// Three-state on purpose, mirroring the patient record: "not asked" and
/// "asked, none known" are clinically different and must not collapse.
enum AllergyRecordState { notRecorded, noneKnown, present }

/// One allergy, flattened for the summary.
typedef AllergyLine = ({String substance, String? severityLabel, bool isHigh});

/// The latest observation set, reduced to what the pre-read shows.
class ObsView {
  const ObsView({
    required this.recordedAt,
    this.risk,
    this.news2Total,
    this.unavailableReason,
  });

  final DateTime recordedAt;
  final News2Risk? risk;
  final int? news2Total;
  final News2Unavailable? unavailableReason;
}

/// A snapshot of one patient's record, assembled once for the builder.
///
/// A pure projection: the data layer maps rows into this, filtering to active
/// problems, current medications and active allergies, so the kernel stays
/// free of DAOs and the builder is testable with fixtures.
class ChartSnapshot {
  const ChartSnapshot({
    required this.patientId,
    required this.asOf,
    required this.allergyState,
    this.allergies = const <AllergyLine>[],
    this.activeProblems = const <String>[],
    this.currentMedications = const <String>[],
    this.latestObs,
    this.lastEncounterAt,
  });

  final String patientId;
  final DateTime asOf;
  final AllergyRecordState allergyState;
  final List<AllergyLine> allergies;
  final List<String> activeProblems;
  final List<String> currentMedications;
  final ObsView? latestObs;
  final DateTime? lastEncounterAt;
}

/// Turns a [ChartSnapshot] into a [RecordSummary].
///
/// Section order is clinical, not incidental: allergies first because they
/// change what is safe to do, then the problem list, medications, the latest
/// observations, and when the patient was last seen.
abstract final class SummaryBuilder {
  static RecordSummary build(ChartSnapshot chart) {
    return RecordSummary(
      patientId: chart.patientId,
      asOf: chart.asOf,
      sections: <SummarySection>[
        _allergies(chart),
        _problems(chart),
        _medications(chart),
        _observations(chart),
        _activity(chart),
      ],
    );
  }

  static SummarySection _allergies(ChartSnapshot c) {
    final item = switch (c.allergyState) {
      AllergyRecordState.notRecorded => const SummaryItem(
          label: 'Allergies',
          value: 'Not recorded',
          state: SummaryState.notRecorded,
          // An unknown allergy status is a safety gap, not a neutral blank.
          severity: FlagSeverity.caution,
          source: 'Patient record',
        ),
      AllergyRecordState.noneKnown => const SummaryItem(
          label: 'Allergies',
          value: 'No known allergies',
          state: SummaryState.recorded,
          source: 'Patient record',
        ),
      AllergyRecordState.present => SummaryItem(
          label: 'Allergies',
          value: _joinAllergies(c.allergies),
          state: SummaryState.recorded,
          severity: c.allergies.any((a) => a.isHigh)
              ? FlagSeverity.critical
              : FlagSeverity.caution,
          source: 'Allergy list',
        ),
    };
    return SummarySection(key: 'allergies', title: 'Allergies', items: [item]);
  }

  static SummarySection _problems(ChartSnapshot c) => _listSection(
        key: 'problems',
        title: 'Active problems',
        label: 'Problems',
        entries: c.activeProblems,
        source: 'Problem list',
      );

  static SummarySection _medications(ChartSnapshot c) => _listSection(
        key: 'medications',
        title: 'Current medications',
        label: 'Medications',
        entries: c.currentMedications,
        source: 'Medication list',
      );

  static SummarySection _observations(ChartSnapshot c) {
    final obs = c.latestObs;
    final SummaryItem item;
    if (obs == null) {
      item = const SummaryItem(
        label: 'Latest observations',
        value: 'Not recorded',
        state: SummaryState.notRecorded,
        severity: FlagSeverity.caution,
        source: 'Observations',
      );
    } else if (obs.risk != null) {
      item = SummaryItem(
        label: 'NEWS2',
        value: 'NEWS2 ${obs.news2Total} · ${obs.risk!.label}',
        state: SummaryState.recorded,
        severity: _bandSeverity(obs.risk!),
        source: 'Observations · ${_stamp(obs.recordedAt)}',
      );
    } else {
      // Observations exist but could not be scored — still recorded, just
      // unscored; say why rather than showing a bare gap.
      item = SummaryItem(
        label: 'Latest observations',
        value: 'Recorded, not scored — ${_unavailableLabel(obs.unavailableReason!)}',
        state: SummaryState.recorded,
        source: 'Observations · ${_stamp(obs.recordedAt)}',
      );
    }
    return SummarySection(
        key: 'observations', title: 'Latest observations', items: [item]);
  }

  static SummarySection _activity(ChartSnapshot c) {
    final last = c.lastEncounterAt;
    final item = last == null
        ? const SummaryItem(
            label: 'Last seen',
            value: 'No prior visits',
            state: SummaryState.notRecorded,
            source: 'Encounters',
          )
        : SummaryItem(
            label: 'Last seen',
            value: _stampDate(last),
            state: SummaryState.recorded,
            source: 'Encounters',
          );
    return SummarySection(key: 'activity', title: 'Last seen', items: [item]);
  }

  /// A list-backed section: an empty structured list is reported as "None
  /// recorded" and marked not-recorded, because empty cannot be distinguished
  /// from never-filled-in — so it must never read as a clean bill.
  static SummarySection _listSection({
    required String key,
    required String title,
    required String label,
    required List<String> entries,
    required String source,
  }) {
    final item = entries.isEmpty
        ? SummaryItem(
            label: label,
            value: 'None recorded',
            state: SummaryState.notRecorded,
            source: source,
          )
        : SummaryItem(
            label: label,
            value: entries.join(', '),
            state: SummaryState.recorded,
            source: source,
          );
    return SummarySection(key: key, title: title, items: [item]);
  }

  static String _joinAllergies(List<AllergyLine> allergies) => allergies
      .map((a) => a.severityLabel == null
          ? a.substance
          : '${a.substance} (${a.severityLabel})')
      .join(', ');

  static FlagSeverity? _bandSeverity(News2Risk risk) => switch (risk) {
        News2Risk.high => FlagSeverity.critical,
        News2Risk.medium => FlagSeverity.caution,
        News2Risk.lowMedium => FlagSeverity.caution,
        News2Risk.low => null,
      };

  static String _unavailableLabel(News2Unavailable reason) => switch (reason) {
        News2Unavailable.ageOutOfScope => 'outside NEWS2 age scope',
        News2Unavailable.pregnancy => 'not scored in pregnancy',
        News2Unavailable.incompleteObservations => 'incomplete set',
      };

  static String _stamp(DateTime t) =>
      '${_stampDate(t)} ${_two(t.hour)}:${_two(t.minute)}';

  static String _stampDate(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');
}
