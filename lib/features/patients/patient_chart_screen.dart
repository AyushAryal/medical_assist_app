import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/routing/app_router.dart';
import '../../data/models/patient.dart';
import '../../data/repositories/clinical_repository.dart';
import '../../core/app_bootstrap.dart';
import '../vitals/vitals.dart';
import 'chart_entry_sheets.dart';
import 'patient_chart_controller.dart';
import 'visit_record_view.dart';
import 'widgets/chart_details.dart';
import 'widgets/chart_lists.dart';
import 'widgets/chart_quick_actions.dart';
import 'widgets/chart_section.dart';
import 'widgets/chart_section_switcher.dart';
import 'widgets/chart_trends.dart';

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
                ChartSectionSwitcher(
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
      ChartQuickActions(chart: chart),
      SizedBox(height: context.metrics.spaceLg),
      SplitColumns(
        primary: <Widget>[
          if (chart.concerningTrends.isNotEmpty)
            TrendAlerts(trends: chart.concerningTrends),
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
          ProblemList(chart: chart),
          MedicationList(chart: chart),
        ],
        secondary: <Widget>[
          AllergyList(chart: chart),
          Demographics(patient: patient, chart: chart),
          Contact(patient: patient),
          LastVisit(chart: chart),
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
        TrendAlerts(trends: chart.concerningTrends),
        SizedBox(height: m.spaceMd),
      ],
      Trends(chart: chart),
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
      FileList(attachments: documents),
    ];
  }
}
