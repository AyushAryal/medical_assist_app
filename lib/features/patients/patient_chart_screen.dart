import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/routing/app_router.dart';
import '../../clinical/news2.dart';
import '../../clinical/summary/referral_letter.dart';
import '../../core/session/session_controller.dart';
import '../../data/models/clinical_note.dart';
import '../../data/models/patient.dart';
import '../../data/repositories/clinical_repository.dart';
import '../../data/services/assist/language_model.dart';
import '../../data/services/letter_pdf.dart';
import '../../core/app_bootstrap.dart';
import '../assist/assist.dart';
import '../vitals/vitals.dart';
import 'chart_entry_sheets.dart';
import 'patient_chart_controller.dart';
import 'smart_intake_screen.dart';
import 'visit_record_view.dart';
import 'widgets/chart_details.dart';
import 'widgets/chart_lists.dart';
import 'widgets/chart_quick_actions.dart';
import 'widgets/chart_section.dart';
import 'widgets/chart_section_switcher.dart';
import 'widgets/chart_trends.dart';
import 'widgets/handoff_sheet.dart';
import 'widgets/record_summary_card.dart';

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

  /// Archive is reversible in the database but absent from the app's lists,
  /// so it gets a spelled-out confirmation, not a casual tap.
  Future<void> _archive(BuildContext context, Patient patient) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Archive ${patient.displayName}?',
      message:
          'The record is kept and audited, but the patient disappears '
          'from lists and search. Nothing is deleted.',
      confirmLabel: 'Archive',
    );
    if (!confirmed || !context.mounted) return;
    await context.read<ClinicalRepository>().archivePatient(patient);
    if (context.mounted) {
      OptToast.success(context, 'Archived ${patient.displayName}.');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const LoadingState();
    }

    return ChangeNotifierProvider<PatientChartController>.value(
      value: controller,
      child: Consumer<PatientChartController>(
        builder: (context, chart, _) {
          if (chart.isLoading) {
            return const LoadingState();
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
                // Cross-cover in one tap: the covering clinician arriving at
                // an unfamiliar chart should not have to find the summary
                // card's Handoff button to get the SBAR glance.
                IconButton(
                  tooltip: 'SBAR handoff',
                  icon: const Icon(Icons.record_voice_over_outlined),
                  onPressed: () => HandoffSheet.showForChart(context, chart),
                ),
                IconButton(
                  tooltip: 'Smart intake',
                  icon: const Icon(Icons.playlist_add),
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SmartIntakeScreen(patientId: patient.id),
                      ),
                    );
                    await chart.refresh();
                  },
                ),
                IconButton(
                  tooltip: 'Edit demographics',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    await context.push(Routes.editFor(patient.id));
                    await chart.refresh();
                  },
                ),
                MenuAnchor(
                  builder: (context, controller, _) => IconButton(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                  menuChildren: <Widget>[
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.archive_outlined),
                      onPressed: () => _archive(context, patient),
                      child: const Text('Archive patient'),
                    ),
                  ],
                ),
              ],
            ),
            body: Column(
              children: <Widget>[
                // 1) Identity — the family-canonical patient header: name,
                // stable avatar seeded from the patient id, and the
                // age · sex · MRN line, in the same place as in every other
                // health app in the family.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    m.spaceLg,
                    m.spaceSm,
                    m.spaceLg,
                    m.spaceSm,
                  ),
                  child: OptPatientHeader(
                    name: patient.displayName,
                    seed: patient.id,
                    meta: <String>[
                      if (patient.age != null)
                        '${patient.dobIsEstimated ? '~' : ''}'
                            '${patient.age!.label}',
                      if (patient.sexAtBirth != SexAtBirth.unknown)
                        patient.sexAtBirth.label,
                      'MRN ${patient.mrn}',
                    ],
                    chips: _headerChips(context, chart, patient),
                    trailing: IconButton.filledTonal(
                      tooltip: chart.openEncounter != null
                          ? 'Resume visit'
                          : 'Start visit',
                      icon: Icon(
                        chart.openEncounter != null
                            ? Icons.play_arrow
                            : Icons.add,
                      ),
                      onPressed: () =>
                          ChartQuickActions.openOrStartVisit(context, chart),
                    ),
                  ),
                ),
                // 2) Alerts. Allergies stay on the full-width banner rather
                // than as header chips: the banner is the more prominent
                // surface and is three-state ("not recorded" included), which
                // chips cannot echo without clutter. Repeating the same
                // substances twice within one screen-height dilutes the
                // signal, so the header carries no allergy chips at all.
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
                          ChartSection.summary => _summary(
                            context,
                            chart,
                            patient,
                          ),
                          ChartSection.history => _history(context, chart),
                          ChartSection.observations => _observations(
                            context,
                            chart,
                            patient,
                          ),
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

  /// Header chips: patient-level states a clinician must see before touching
  /// the chart. Allergies are deliberately absent — the [AllergyBanner]
  /// directly below is the more prominent, three-state safety surface.
  List<PatientHeaderChip> _headerChips(
    BuildContext context,
    PatientChartController chart,
    Patient patient,
  ) {
    final palette = context.palette;
    final vitals = chart.latestVitals;
    final risk = vitals == null
        ? null
        : News2Risk.values.where((r) => r.name == vitals.news2Risk).firstOrNull;
    return <PatientHeaderChip>[
      if (patient.isDeceased) const PatientHeaderChip('Deceased'),
      // The risk band from the latest scored observation set. Colour comes
      // from the app's own clinical severity tokens, and the band name is
      // always in the label — colour is never the only channel.
      if (risk != null && vitals!.news2Score != null)
        PatientHeaderChip(
          'NEWS2 ${vitals.news2Score} · ${risk.label}',
          icon: Icons.monitor_heart_outlined,
          color: switch (risk) {
            News2Risk.high => palette.critical,
            News2Risk.medium || News2Risk.lowMedium => palette.caution,
            News2Risk.low => palette.normal,
          },
        ),
    ];
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
    final summary = chart.recordSummary;
    final aiActive = context.watch<AppBootstrap>().assistModelActive;
    // The exact record lines fed to the model — shown behind "Sources" so the
    // output is grounded in real entries, never invented citations.
    final sources = summary == null
        ? const <AiSource>[]
        : <AiSource>[
            for (final item in summary.allItems)
              AiSource(label: item.label, detail: item.source),
          ];
    // The latest signed note — the single most-reviewed chart artifact
    // (chart-biopsy: the median review reads exactly one prior note), so it
    // gets a first-class card directly under the visit action. Signed-only:
    // a draft is not yet record, and the card must never leak scratch text.
    final lastSigned = chart.visits
        .where((v) => v.note != null && v.note!.isLocked && !v.note!.isEmpty)
        .firstOrNull;
    final lastNote = lastSigned?.note;

    return <Widget>[
      ChartQuickActions(chart: chart),
      SizedBox(height: context.metrics.spaceLg),
      // Gap rule: the card and its spacer exist together or not at all — an
      // absent note must not leave an unexplained block of gap behind.
      if (lastSigned != null && lastNote != null) ...<Widget>[
        OptLastNoteCard(
          label: 'Last note · ${lastNote.noteType.label}',
          // Preview from the first non-empty SOAP section, in read order.
          text: <String?>[
            lastNote.subjective,
            lastNote.objective,
            lastNote.assessment,
            lastNote.plan,
          ].map((s) => s?.trim()).firstWhere((s) => s != null && s.isNotEmpty),
          author: lastNote.signedBy,
          date: lastNote.signedAt ?? lastNote.updatedAt,
          // The note route renders locked notes read-only (signature bar, no
          // fields), so tapping through respects the signed/amended state.
          onTap: () async {
            await context.push(Routes.noteFor(lastSigned.encounter.id));
            await chart.refresh();
          },
        ),
        SizedBox(height: context.metrics.spaceLg),
      ],
      if (summary != null) ...<Widget>[
        RecordSummaryCard(
          summary: summary,
          onHandoff: () => HandoffSheet.showForChart(context, chart),
          onBrief: !aiActive
              ? null
              : () => AiDraftSheet.show(
                  context,
                  title: 'Spoken brief',
                  subtitle: patient.displayName,
                  notice:
                      'Generated from the record. Read it before you '
                      'rely on it.',
                  sources: sources,
                  generate: (engine) => engine.spokenBrief(summary.plainText),
                ),
          onExplain: !aiActive
              ? null
              : () => AiDraftSheet.show(
                  context,
                  title: 'Explain',
                  subtitle: patient.displayName,
                  caveat:
                      'Describes the numbers only — not a diagnosis or '
                      'advice.',
                  notice: 'Generated from the record shown above.',
                  sources: sources,
                  generate: (engine) =>
                      engine.explainPlainly(summary.plainText),
                ),
          onReferral: !aiActive
              ? null
              : () {
                  final session = context.read<SessionController>();
                  AiDraftSheet.show(
                    context,
                    title: 'Referral letter',
                    subtitle: patient.displayName,
                    notice:
                        'Draft from the record — check every line before '
                        'sending. The record is the source of truth.',
                    sources: sources,
                    // The clinician corrects the draft in place; copy, the
                    // PDF and the emailed attachment all follow the edits.
                    editable: true,
                    patientId: patient.id,
                    letter: LetterPdf(
                      title: 'Referral letter',
                      clinicianName: session.signatureName,
                      clinicName: session.activeClinic?.name,
                      patientName: patient.displayName,
                      patientDetails: <String>[patient.identityLine],
                    ),
                    generate: (engine) async {
                      // The letter is composed deterministically from the
                      // record; the model only polishes the prose. If it
                      // fails, echoes, or mangles the draft, the composed
                      // letter stands — a field dump is never shown again.
                      final base = ReferralLetterComposer.compose(
                        patient: patient,
                        reason: chart.encounters.firstOrNull?.chiefComplaint,
                        problems: chart.problems,
                        medications: chart.medications,
                        allergies: chart.allergies,
                        latestVitals: chart.latestVitals,
                      );
                      final polished = await engine.referralLetter(base);
                      final text = polished.text.trim();
                      final surname = patient.familyName.trim().toLowerCase();
                      final usable =
                          text.length >= 120 &&
                          !text.contains('Referring clinician:') &&
                          (surname.isEmpty ||
                              text.toLowerCase().contains(surname));
                      return usable
                          ? polished
                          : LanguageModelDraft(
                              text: base,
                              engineName: 'record template',
                            );
                    },
                  );
                },
        ),
        SizedBox(height: context.metrics.spaceLg),
      ],
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
          // Hoisted: LastVisit renders nothing without a visit, but
          // SplitColumns interleaves a gap before every listed child — an
          // absent panel must not leave its spacer behind.
          if (chart.visits.isNotEmpty) LastVisit(chart: chart),
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
          message:
              'Start a visit from the Summary tab and it will appear here.',
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
      // Trends collapses to nothing with fewer than two plottable sets, so it
      // carries its own bottom spacing — a bare spacer here would survive the
      // card it was spacing and leave an unexplained gap.
      Trends(chart: chart),
      // Every set, newest first — the numbers behind the sparklines. Indexed
      // rather than `indexOf`, which would rescan the list for every row and
      // pick the wrong neighbour for two identical records. Spacers only
      // between cards — the list's own bottom padding closes the page.
      for (var i = 0; i < chart.vitals.length; i++) ...<Widget>[
        if (i > 0) SizedBox(height: m.spaceMd),
        VitalsSummaryCard(
          vitals: chart.vitals[i],
          previous: i + 1 < chart.vitals.length ? chart.vitals[i + 1] : null,
          age: chart.age,
        ),
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
          message:
              'Photos, documents and dictation attached during a visit '
              'appear here.',
        ),
      ];
    }

    return <Widget>[FileList(attachments: documents)];
  }
}
