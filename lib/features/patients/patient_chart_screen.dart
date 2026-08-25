import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../clinical/insights/trend_analysis.dart';
import '../../core/design/design.dart';

import '../../core/routing/app_router.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/allergy.dart';
import '../../data/models/patient.dart';
import '../../data/models/attachment.dart';
import '../../data/repositories/clinical_repository.dart';
import '../../core/app_bootstrap.dart';
import '../appointments/book_appointment_sheet.dart';
import '../encounters/start_encounter_sheet.dart';
import '../../data/services/assist/assist_service.dart';
import '../vitals/vitals_summary_card.dart';
import 'chart_entry_sheets.dart';
import 'patient_chart_controller.dart';
import 'visit_record_view.dart';

/// Which part of the chart is on screen.
///
/// A chart holds more than fits on one scroll, and the previous single column
/// meant the visit history — the thing most often wanted — was always at the
/// bottom past six other panels. Splitting it costs one tap and saves the
/// scroll; the split is by *question being asked*, not by data type:
///
/// * **Summary** — "what do I need to know before I walk in?"
/// * **History** — "what happened last time, and the time before?"
/// * **Observations** — "which way is this going?"
/// * **Files** — "where is the X-ray?"
enum ChartSection { summary, history, observations, files }

extension ChartSectionX on ChartSection {
  String get label => switch (this) {
        ChartSection.summary => 'Summary',
        ChartSection.history => 'History',
        ChartSection.observations => 'Observations',
        ChartSection.files => 'Files',
      };

  IconData get icon => switch (this) {
        ChartSection.summary => Icons.badge_outlined,
        ChartSection.history => Icons.history_outlined,
        ChartSection.observations => Icons.show_chart,
        ChartSection.files => Icons.folder_outlined,
      };
}

/// The patient chart: everything known about one person, in the order a
/// clinician reads it.
class PatientChartScreen extends StatefulWidget {
  const PatientChartScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientChartScreen> createState() => _PatientChartScreenState();
}

class _PatientChartScreenState extends State<PatientChartScreen> {
  PatientChartController? _controller;
  ChartSection _section = ChartSection.summary;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = PatientChartController(
      context.read<ClinicalRepository>(),
      widget.patientId,
      assist: context.read<AppBootstrap>().assist,
    );
    _controller!.load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ChangeNotifierProvider<PatientChartController>.value(
      value: controller,
      child: Consumer<PatientChartController>(
        builder: (context, chart, _) {
          if (chart.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final patient = chart.patient;
          if (patient == null) {
            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(),
              body: const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Patient not found',
                message: 'This record may have been removed.',
              ),
            );
          }

          final m = context.metrics;

          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Text(patient.displayName),
              actions: <Widget>[
                CallButton(
                  phone: patient.phone,
                  patientName: patient.displayName,
                  compact: true,
                ),
                IconButton(
                  tooltip: 'Edit demographics',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    await context.push(Routes.editFor(patient.id));
                    await chart.refresh();
                  },
                ),
              ],
            ),
            body: Column(
              children: <Widget>[
                PatientIdentityBar(patient: patient),
                AllergyBanner(
                  status: patient.allergyStatus,
                  allergies: chart.allergies,
                  onTap: () => AllergySheet.show(context, chart),
                ),
                _SectionSwitcher(
                  section: _section,
                  onChanged: (section) => setState(() => _section = section),
                  visitCount: chart.visits.length,
                  fileCount: chart.attachments.length,
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: chart.refresh,
                    child: ContentWidth.columns(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          m.spaceLg,
                          m.spaceMd,
                          m.spaceLg,
                          m.space2xl * 2,
                        ),
                        children: switch (_section) {
                          ChartSection.summary =>
                            _summary(context, chart, patient),
                          ChartSection.history => _history(context, chart),
                          ChartSection.observations =>
                            _observations(context, chart, patient),
                          ChartSection.files => _files(context, chart),
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// What is needed before walking into the room.
  ///
  /// Two editorial columns on a wide screen rather than a balanced flow: which
  /// panel the eye lands on first is a safety property here, and allergies and
  /// active problems must not migrate to the bottom of a second column because
  /// the columns balanced better that way.
  List<Widget> _summary(
    BuildContext context,
    PatientChartController chart,
    Patient patient,
  ) {
    return <Widget>[
      _QuickActions(chart: chart),
      SizedBox(height: context.metrics.spaceLg),
      SplitColumns(
        primary: <Widget>[
          if (chart.concerningTrends.isNotEmpty)
            _TrendAlerts(trends: chart.concerningTrends),
          if (chart.latestVitals != null)
            VitalsSummaryCard(
              vitals: chart.latestVitals!,
              previous: chart.previousVitals,
              age: chart.age,
              onRecord: () async {
                await context.push(Routes.vitalsFor(patient.id));
                await chart.refresh();
              },
            ),
          _ProblemList(chart: chart),
          _MedicationList(chart: chart),
        ],
        secondary: <Widget>[
          _AllergyList(chart: chart),
          _Demographics(patient: patient, chart: chart),
          _Contact(patient: patient),
          _LastVisit(chart: chart),
        ],
      ),
    ];
  }

  /// Every visit, readable in place.
  List<Widget> _history(BuildContext context, PatientChartController chart) {
    final m = context.metrics;

    if (chart.visits.isEmpty) {
      return const <Widget>[
        EmptyState(
          icon: Icons.event_note_outlined,
          title: 'No visits recorded',
          message: 'Start a visit from the Summary tab and it will appear here.',
        ),
      ];
    }

    return <Widget>[
      for (final visit in chart.visits)
        Padding(
          padding: EdgeInsets.only(bottom: m.spaceMd),
          child: GlassPanel(
            padding: EdgeInsets.all(m.spaceLg),
            child: VisitRecordView(
              visit: visit,
              patient: chart.patient!,
              age: chart.age,
              dense: true,
            ),
          ),
        ),
      if (chart.hasOlderVisits)
        Padding(
          padding: EdgeInsets.only(top: m.spaceSm),
          child: Text(
            'Showing the most recent ${PatientChartController.visitHistoryLimit} '
            'of ${chart.encounters.length} visits.',
            textAlign: TextAlign.center,
            style: context.texts.labelSmall,
          ),
        ),
    ];
  }

  List<Widget> _observations(
    BuildContext context,
    PatientChartController chart,
    Patient patient,
  ) {
    final m = context.metrics;

    if (chart.vitals.isEmpty) {
      return <Widget>[
        EmptyState(
          icon: Icons.monitor_heart_outlined,
          title: 'No observations recorded',
          message: 'Record a set of vital signs to start a trend.',
          actionLabel: 'Record observations',
          onAction: () async {
            await context.push(Routes.vitalsFor(patient.id));
            await chart.refresh();
          },
        ),
      ];
    }

    return <Widget>[
      if (chart.concerningTrends.isNotEmpty) ...<Widget>[
        _TrendAlerts(trends: chart.concerningTrends),
        SizedBox(height: m.spaceMd),
      ],
      _Trends(chart: chart),
      SizedBox(height: m.spaceMd),
      // Every set, newest first — the numbers behind the sparklines. Indexed
      // rather than `indexOf`, which would rescan the list for every row and
      // pick the wrong neighbour for two identical records.
      for (var i = 0; i < chart.vitals.length; i++) ...<Widget>[
        VitalsSummaryCard(
          vitals: chart.vitals[i],
          previous:
              i + 1 < chart.vitals.length ? chart.vitals[i + 1] : null,
          age: chart.age,
        ),
        SizedBox(height: m.spaceMd),
      ],
    ];
  }

  List<Widget> _files(BuildContext context, PatientChartController chart) {
    final documents = chart.documents;
    if (documents.isEmpty) {
      return const <Widget>[
        EmptyState(
          icon: Icons.folder_outlined,
          title: 'No files yet',
          message: 'Photos, documents and dictation attached during a visit '
              'appear here.',
        ),
      ];
    }

    return <Widget>[
      _FileList(attachments: documents),
    ];
  }
}

/// Moves between the four parts of the chart.
class _SectionSwitcher extends StatelessWidget {
  const _SectionSwitcher({
    required this.section,
    required this.onChanged,
    required this.visitCount,
    required this.fileCount,
  });

  final ChartSection section;
  final ValueChanged<ChartSection> onChanged;
  final int visitCount;
  final int fileCount;

  String _label(ChartSection value) => switch (value) {
        ChartSection.history when visitCount > 0 =>
          '${value.label} ($visitCount)',
        ChartSection.files when fileCount > 0 => '${value.label} ($fileCount)',
        _ => value.label,
      };

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: m.spaceLg,
        vertical: m.spaceSm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: palette.outline, width: m.hairline),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final value in ChartSection.values)
              Padding(
                padding: EdgeInsets.only(right: m.spaceSm),
                child: ChoiceChip(
                  selected: value == section,
                  showCheckmark: false,
                  avatar: Icon(
                    value.icon,
                    size: 16,
                    color: value == section
                        ? palette.onPrimaryContainer
                        : palette.onSurfaceMuted,
                  ),
                  label: Text(_label(value)),
                  onSelected: (_) => onChanged(value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The three things done most often on an open chart, one tap each.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.chart});

  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final patient = chart.patient!;
    final open = chart.openEncounter;

    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: () async {
              if (open != null) {
                await context.push(Routes.encounterFor(open.id));
              } else {
                final encounter = await StartEncounterSheet.show(
                  context,
                  patient: patient,
                );
                if (encounter != null && context.mounted) {
                  await context.push(Routes.encounterFor(encounter.id));
                }
              }
              await chart.refresh();
            },
            icon: Icon(open != null ? Icons.play_arrow : Icons.add),
            label: Text(open != null ? 'Resume visit' : 'Start visit'),
          ),
        ),
        SizedBox(width: m.spaceSm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              await context.push(Routes.vitalsFor(patient.id));
              await chart.refresh();
            },
            icon: const Icon(Icons.monitor_heart_outlined),
            label: const Text('Vitals'),
          ),
        ),
        SizedBox(width: m.spaceSm),
        IconButton.filledTonal(
          tooltip: 'Book an appointment',
          icon: const Icon(Icons.event_available_outlined),
          onPressed: () async {
            await BookAppointmentSheet.show(context, patient: patient);
            await chart.refresh();
          },
        ),
      ],
    );
  }
}

/// Vital-sign trends. Direction over time is often more informative than any
/// single reading — a pulse climbing 70 → 95 → 118 matters even while each
/// value is still inside its reference band.
class _Trends extends StatelessWidget {
  const _Trends({required this.chart});

  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    // Oldest first for plotting; the DAO returns newest first.
    final history = chart.vitals.reversed.toList();
    if (history.length < 2) return const SizedBox.shrink();

    final palette = context.palette;
    final m = context.metrics;

    final series = <({String label, List<double?> values, Color color})>[
      (
        label: 'Systolic BP',
        values: history.map((v) => v.systolicBp?.toDouble()).toList(),
        color: palette.primary,
      ),
      (
        label: 'Pulse',
        values: history.map((v) => v.heartRate?.toDouble()).toList(),
        color: palette.accent,
      ),
      (
        label: 'Temperature',
        values: history.map((v) => v.temperatureC).toList(),
        color: palette.caution,
      ),
      (
        label: 'Weight',
        values: history.map((v) => v.weightKg).toList(),
        color: palette.info,
      ),
    ].where((s) => s.values.whereType<double>().length >= 2).toList();

    if (series.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      title: 'Trends',
      subtitle: '${history.length} observation sets',
      leading: const Icon(Icons.show_chart, size: 20),
      child: Column(
        children: <Widget>[
          for (final s in series)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceMd),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 96,
                    child: Text(s.label, style: context.texts.labelSmall),
                  ),
                  Expanded(
                    child: Sparkline(values: s.values, color: s.color),
                  ),
                  SizedBox(width: m.spaceSm),
                  SizedBox(
                    width: 44,
                    child: Text(
                      Fmt.number(s.values.whereType<double>().last),
                      textAlign: TextAlign.right,
                      style: context.texts.labelMedium?.copyWith(
                        color: s.color,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Contact',
      leading: const Icon(Icons.contact_phone_outlined, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ContactRow(
            phone: patient.phone,
            altPhone: patient.altPhone,
            patientName: patient.displayName,
          ),
          if (patient.nextOfKinName != null) ...<Widget>[
            SectionCard.divider(context),
            Text(
              'Next of kin — ${patient.nextOfKinName}'
              '${patient.nextOfKinRelation == null ? '' : ' (${patient.nextOfKinRelation})'}',
              style: context.texts.labelMedium,
            ),
            SizedBox(height: context.metrics.spaceSm),
            ContactRow(
              phone: patient.nextOfKinPhone,
              patientName: patient.nextOfKinName!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProblemList extends StatelessWidget {
  const _ProblemList({required this.chart});

  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final active = chart.activeProblems;
    final resolved = chart.problems.where((p) => !p.isActive).length;

    return SectionCard(
      title: 'Problem list',
      subtitle: resolved == 0 ? null : '$resolved resolved',
      leading: const Icon(Icons.checklist_outlined, size: 20),
      trailing: IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Add problem',
        onPressed: () => ProblemSheet.show(context, chart),
      ),
      child: active.isEmpty
          ? const EmptyState(
              icon: Icons.checklist_outlined,
              title: 'No active problems',
              message: 'Add a diagnosis to build the problem list.',
              compact: true,
            )
          : Column(
              children: active.map((problem) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(problem.display),
                  subtitle: Text(
                    <String>[
                      if (problem.codeLabel.isNotEmpty) problem.codeLabel,
                      if (problem.onsetDate != null)
                        'since ${Fmt.date(problem.onsetDate)}',
                    ].join(' · '),
                  ),
                  trailing: problem.isChronic
                      ? const StatusPill(
                          label: 'Chronic',
                          tone: PillTone.info,
                          dense: true,
                        )
                      : null,
                );
              }).toList(),
            ),
    );
  }
}

class _MedicationList extends StatelessWidget {
  const _MedicationList({required this.chart});

  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final active = chart.activeMedications;

    return SectionCard(
      title: 'Current medications',
      leading: const Icon(Icons.medication_outlined, size: 20),
      trailing: IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Add medication',
        onPressed: () => MedicationSheet.show(context, chart),
      ),
      child: active.isEmpty
          ? const EmptyState(
              icon: Icons.medication_outlined,
              title: 'No current medications',
              compact: true,
            )
          : Column(
              children: active.map((medication) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(medication.sig),
                  subtitle: medication.indication == null
                      ? null
                      : Text('for ${medication.indication}'),
                );
              }).toList(),
            ),
    );
  }
}

class _AllergyList extends StatelessWidget {
  const _AllergyList({required this.chart});

  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final active = chart.allergies.where((a) => a.isActive).toList();

    return SectionCard(
      title: 'Allergies',
      leading: const Icon(Icons.warning_amber_outlined, size: 20),
      trailing: IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Add allergy',
        onPressed: () => AllergySheet.show(context, chart),
      ),
      child: active.isEmpty
          ? EmptyState(
              icon: Icons.info_outline,
              title: chart.patient!.allergyStatus.label,
              message: chart.patient!.allergyStatus == AllergyStatus.unknown
                  ? 'Ask the patient and record the answer either way.'
                  : null,
              compact: true,
            )
          : Column(
              children: active.map((allergy) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(allergy.substance),
                  subtitle: Text(
                    <String>[
                      allergy.category.label,
                      if (allergy.reaction?.isNotEmpty == true)
                        allergy.reaction!,
                    ].join(' · '),
                  ),
                  trailing: StatusPill(
                    label: allergy.severity.label,
                    tone: allergy.severity.isHighRisk
                        ? PillTone.critical
                        : PillTone.caution,
                    dense: true,
                  ),
                );
              }).toList(),
            ),
    );
  }
}

/// Observations moving the wrong way.
///
/// This is the one panel in the chart that says something no single reading
/// can: a pulse of 70, then 95, then 118 is three defensible adult values and a
/// patient deteriorating in front of you. It is shown only when there is
/// something to show — a panel that usually reads "no concerns" is one that
/// stops being read, including on the day it matters.
class _TrendAlerts extends StatelessWidget {
  const _TrendAlerts({required this.trends});

  final List<TrendResult> trends;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Callout(
      title: trends.length == 1
          ? 'One observation is moving the wrong way'
          : '${trends.length} observations are moving the wrong way',
      icon: Icons.trending_up,
      tone: palette.caution,
      subtitle: 'Direction across recorded visits — every reading may still be '
          'inside its reference band.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: const AiBadge(label: 'Detected', dense: true),
          ),
          for (final trend in trends)
            Padding(
              padding: EdgeInsets.only(top: m.spaceSm),
              child: Row(
                children: <Widget>[
                  Icon(
                    trend.direction == TrendDirection.rising
                        ? Icons.north_east
                        : Icons.south_east,
                    size: 15,
                    color: palette.caution,
                  ),
                  SizedBox(width: m.spaceSm),
                  Expanded(
                    child: Text(
                      '${trend.label} ${trend.direction.label} — '
                      '${trend.first.toStringAsFixed(0)} to '
                      '${trend.last.toStringAsFixed(0)} '
                      '${AssistService.unitFor(trend.label)} '
                      'over ${trend.points} readings',
                      style: context.texts.bodySmall,
                    ),
                  ),
                  InfoDot(
                    explanation: TrendAnalysis.explain(
                      trend,
                      AssistService.unitFor(trend.label),
                    ),
                    semanticLabel: 'How this trend was worked out',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The identity facts that drive dosing and reference ranges.
///
/// Sex at birth and gender identity are shown separately because they do
/// different jobs: the first selects reference ranges and drug dosing, the
/// second is how the patient is addressed. Collapsing them loses one or
/// insults the patient.
class _Demographics extends StatelessWidget {
  const _Demographics({required this.patient, required this.chart});

  final Patient patient;
  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final age = chart.age;

    return SectionCard(
      title: 'Patient details',
      leading: const Icon(Icons.badge_outlined, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DetailRow(label: 'MRN', value: patient.mrn),
          DetailRow(
            label: 'Age',
            value: age == null
                ? 'Not recorded'
                : patient.dobIsEstimated
                    ? '~${age.label} (approximate)'
                    : age.label,
          ),
          DetailRow(
            label: 'Date of birth',
            value: patient.dateOfBirth == null
                ? 'Not recorded'
                : patient.dobIsEstimated
                    // Never print a birthday the record cannot support: an
                    // approximate age is stored as 1 January.
                    ? 'Year ${patient.dateOfBirth!.year}, estimated'
                    : Fmt.date(patient.dateOfBirth),
          ),
          DetailRow(label: 'Sex at birth', value: patient.sexAtBirth.label),
          if (patient.genderIdentity?.isNotEmpty ?? false)
            DetailRow(label: 'Gender', value: patient.genderIdentity!),
          if (patient.bloodGroup?.isNotEmpty ?? false)
            DetailRow(label: 'Blood group', value: patient.bloodGroup!),
          if (patient.nationalId?.isNotEmpty ?? false)
            DetailRow(label: 'National ID', value: patient.nationalId!),
          if (patient.occupation?.isNotEmpty ?? false)
            DetailRow(label: 'Occupation', value: patient.occupation!),
          if (patient.addressLine?.isNotEmpty ?? false)
            DetailRow(
              label: 'Address',
              value: <String>[
                patient.addressLine!,
                if (patient.city?.isNotEmpty ?? false) patient.city!,
                if (patient.district?.isNotEmpty ?? false) patient.district!,
              ].join(', '),
            ),
          if (patient.isDeceased)
            DetailRow(
              label: 'Deceased',
              value: Fmt.date(patient.deceasedDate),
            ),
        ],
      ),
    );
  }
}

/// The last visit, in full, on the summary tab.
///
/// "What happened last time" is the question asked before almost every
/// consultation, and it should not cost a tab change to answer.
class _LastVisit extends StatelessWidget {
  const _LastVisit({required this.chart});

  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final visit = chart.visits.firstOrNull;
    if (visit == null) return const SizedBox.shrink();

    return SectionCard(
      title: 'Last visit',
      subtitle: Fmt.relative(visit.encounter.startedAt),
      leading: const Icon(Icons.history_outlined, size: 20),
      child: VisitRecordView(
        visit: visit,
        patient: chart.patient!,
        age: chart.age,
        dense: true,
      ),
    );
  }
}

/// Everything attached to this patient, newest first.
class _FileList extends StatelessWidget {
  const _FileList({required this.attachments});

  final List<Attachment> attachments;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return SectionCard(
      title: 'Files',
      subtitle: '${attachments.length} item'
          '${attachments.length == 1 ? '' : 's'}',
      leading: const Icon(Icons.folder_outlined, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final attachment in attachments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                switch (attachment.kind) {
                  AttachmentKind.photo => Icons.image_outlined,
                  AttachmentKind.document => Icons.description_outlined,
                  AttachmentKind.audio => Icons.graphic_eq,
                  AttachmentKind.video => Icons.videocam_outlined,
                },
                color: palette.onSurfaceMuted,
              ),
              title: Text(attachment.caption ?? attachment.fileName),
              subtitle: Text(
                <String>[
                  Fmt.date(attachment.capturedAt ?? attachment.createdAt),
                  // Both return an empty string rather than null when the
                  // underlying value is missing.
                  attachment.sizeLabel,
                  attachment.durationLabel,
                  if (attachment.bodySite?.isNotEmpty ?? false)
                    attachment.bodySite!,
                ].where((part) => part.isNotEmpty).join(' · '),
              ),
            ),
          SizedBox(height: m.spaceXs),
          Text(
            'Files are opened from the visit they belong to, where the note '
            'that explains them is alongside.',
            style: context.texts.labelSmall,
          ),
        ],
      ),
    );
  }
}
