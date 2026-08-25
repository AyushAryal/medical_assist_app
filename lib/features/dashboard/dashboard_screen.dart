import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../clinical/news2.dart';
import '../../core/routing/app_router.dart';
import '../../core/session/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/appointment.dart';
import '../../data/models/encounter.dart';
import '../../data/models/patient.dart';
import '../../data/repositories/clinical_repository.dart';
import '../appointments/appointment_tile.dart';
import '../appointments/book_appointment_sheet.dart';
import '../clinics/clinic_picker_sheet.dart';
import 'dashboard_controller.dart';

/// The screen a clinician opens the app onto.
///
/// Ordered by what is actually pending: who is here now, what is booked, what
/// is unfinished, and who needs a second look. Reference numbers come last —
/// "registered patients" is context, not a task.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = DashboardController(context.read<ClinicalRepository>());
    _reload();
  }

  Future<void> _reload() async {
    final session = context.read<SessionController>();
    await _controller?.load(clinicId: session.activeClinic?.id);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _bookForPatient() async {
    final patientId = await _pickPatient();
    if (patientId == null || !mounted) return;
    final patient = await context.read<ClinicalRepository>().patients.byId(patientId);
    if (patient == null || !mounted) return;
    await BookAppointmentSheet.show(context, patient: patient);
    await _reload();
  }

  /// Lightweight patient picker so booking does not require leaving the
  /// dashboard and navigating the full patient list.
  Future<String?> _pickPatient() async {
    final repository = context.read<ClinicalRepository>();
    final recent = await repository.patients.recent(limit: 30);
    if (!mounted) return null;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(context.metrics.spaceLg),
              child: Text('Choose patient', style: context.texts.titleMedium),
            ),
            if (recent.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No patients registered yet.'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: recent.length,
                  itemBuilder: (context, index) {
                    final patient = recent[index];
                    return ListTile(
                      leading: PatientAvatar(
                        initials: patient.initials,
                        seed: patient.id,
                        radius: 18,
                      ),
                      title: Text(patient.displayName),
                      subtitle: Text(patient.identityLine),
                      onTap: () => Navigator.of(context).pop(patient.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final session = context.watch<SessionController>();
    final m = context.metrics;

    return ChangeNotifierProvider<DashboardController>.value(
      value: controller,
      child: Consumer<DashboardController>(
        builder: (context, dashboard, _) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: <Widget>[
                RefreshIndicator(
                  onRefresh: _reload,
                  child: ContentWidth.columns(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        m.spaceLg,
                        0,
                        m.spaceLg,
                        m.space2xl * 2,
                      ),
                      children: <Widget>[
                        SafeArea(
                          bottom: false,
                          child: SizedBox(height: m.spaceSm),
                        ),
                        _Header(
                          greeting: _greeting(DateTime.now()),
                          name: session.providerName,
                          clinicName: session.activeClinic?.name,
                          onSwitchClinic: () async {
                            await ClinicPickerSheet.show(context);
                            if (context.mounted) await _reload();
                          },
                        ),
                        SizedBox(height: m.spaceLg),
                        // Who is next, and anything abnormal, always come
                        // first and always full width — they are the two
                        // things that must not be missed, and putting them in
                        // a column would let the layout decide their
                        // prominence.
                        _NextUpCard(dashboard: dashboard, onChanged: _reload),
                        SizedBox(height: m.spaceLg),
                        _NeedsAttention(dashboard: dashboard),
                        _QuickActions(
                          dashboard: dashboard,
                          onBook: _bookForPatient,
                          onChanged: _reload,
                        ),
                        SizedBox(height: m.spaceLg),
                        // Below the fold the panels are independent, so a wide
                        // screen runs them in two columns rather than a single
                        // strip between two empty margins.
                        SplitColumns(
                          primary: <Widget>[
                            _TodaySchedule(dashboard: dashboard),
                            _OpenWork(dashboard: dashboard, onChanged: _reload),
                          ],
                          secondary: <Widget>[
                            _AtAGlance(dashboard: dashboard),
                            _RecentPatients(dashboard: dashboard),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Sits above the scrolling list so content passing beneath the
                // status bar stays legible.
                const StatusBarScrim(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.greeting,
    required this.name,
    required this.clinicName,
    required this.onSwitchClinic,
  });

  final String greeting;
  final String name;
  final String? clinicName;
  final VoidCallback onSwitchClinic;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final trimmed = name.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          Fmt.weekday(DateTime.now()).toUpperCase(),
          style: context.texts.labelSmall?.copyWith(letterSpacing: 1.1),
        ),
        SizedBox(height: m.spaceXs),
        Text(
          trimmed.isEmpty ? greeting : '$greeting, $trimmed',
          style: context.texts.headlineMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: m.spaceMd),
        // Always visible and always one tap away: filing an encounter against
        // the wrong site produces a record nobody can find.
        Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: palette.surface,
            borderRadius: BorderRadius.circular(m.radiusLg),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onSwitchClinic,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: m.spaceMd,
                  vertical: m.spaceSm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.location_on_outlined,
                        size: 16, color: palette.primary),
                    SizedBox(width: m.spaceXs + 2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        clinicName ?? 'No clinic selected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelMedium,
                      ),
                    ),
                    SizedBox(width: m.spaceXs),
                    Icon(Icons.unfold_more,
                        size: 15, color: palette.onSurfaceMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The single most useful thing on the screen: who is next, and one tap to
/// start seeing them.
class _NextUpCard extends StatelessWidget {
  const _NextUpCard({required this.dashboard, required this.onChanged});

  final DashboardController dashboard;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final next = dashboard.nextUp;

    if (next == null) {
      final nothingBooked = dashboard.todaySchedule.isEmpty;
      return Container(
        padding: EdgeInsets.all(m.spaceLg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(m.radiusMd),
          color: palette.primaryContainer,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(m.radiusSm),
              ),
              child: Icon(
                nothingBooked ? Icons.event_available_outlined : Icons.task_alt,
                color: palette.onPrimaryContainer,
              ),
            ),
            SizedBox(width: m.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    nothingBooked ? 'No clinic booked today' : 'Clinic list clear',
                    style: context.texts.titleMedium
                        ?.copyWith(color: palette.onPrimaryContainer),
                  ),
                  Text(
                    nothingBooked
                        ? 'Book a visit, or see a walk-in straight from a chart.'
                        : 'Everyone booked for today has been seen.',
                    style: context.texts.bodySmall
                        ?.copyWith(color: palette.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final appointment = next.appointment;
    final waiting = appointment.waitingFor;

    return Container(
      padding: EdgeInsets.all(m.spaceLg),
      decoration: BoxDecoration(
        color: palette.heroSurface,
        borderRadius: BorderRadius.circular(m.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.arrow_forward, size: 15, color: palette.onHeroSurface),
              SizedBox(width: m.spaceXs + 2),
              Text(
                waiting != null ? 'WAITING NOW' : 'NEXT UP',
                style: context.texts.labelSmall?.copyWith(
                  color: palette.onHeroSurface.withValues(alpha: 0.85),
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                Fmt.time(appointment.scheduledAt),
                style: context.texts.labelLarge
                    ?.copyWith(color: palette.onHeroSurface),
              ),
            ],
          ),
          SizedBox(height: m.spaceMd),
          Text(
            next.patient.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.headlineSmall
                ?.copyWith(color: palette.onHeroSurface),
          ),
          Text(
            <String>[
              next.patient.identityLine,
              if (appointment.reason != null) appointment.reason!,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodySmall?.copyWith(
              color: palette.onHeroSurface.withValues(alpha: 0.85),
            ),
          ),
          if (waiting != null) ...<Widget>[
            SizedBox(height: m.spaceSm),
            Text(
              'Waiting ${waiting.inMinutes} min',
              style: context.texts.labelMedium?.copyWith(
                color: palette.onHeroSurface.withValues(alpha: 0.9),
              ),
            ),
          ],
          SizedBox(height: m.spaceLg),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.onHeroSurface,
                    foregroundColor: palette.heroSurface,
                  ),
                  onPressed: () async {
                    final repository = context.read<ClinicalRepository>();
                    final session = context.read<SessionController>();
                    final encounter = await repository.startFromAppointment(
                      appointment,
                      providerName: session.signatureName,
                    );
                    if (context.mounted) {
                      await context.push(Routes.encounterFor(encounter.id));
                    }
                    await onChanged();
                  },
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Start visit'),
                ),
              ),
              SizedBox(width: m.spaceSm),
              IconButton.filledTonal(
                tooltip: 'Open chart',
                style: IconButton.styleFrom(
                  backgroundColor: palette.onHeroSurface.withValues(alpha: 0.18),
                  foregroundColor: palette.onPrimary,
                ),
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: () => context.push(Routes.chartFor(next.patient.id)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.dashboard,
    required this.onBook,
    required this.onChanged,
  });

  final DashboardController dashboard;
  final Future<void> Function() onBook;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    final actions = <Widget>[
      QuickAction(
        icon: Icons.person_add_alt,
        label: 'New patient',
        tone: palette.primary,
        onTap: () async {
          await context.push(Routes.patientNew);
          await onChanged();
        },
      ),
      QuickAction(
        icon: Icons.event_available_outlined,
        label: 'Book visit',
        tone: palette.accent,
        onTap: onBook,
      ),
      QuickAction(
        icon: Icons.chair_outlined,
        label: 'Waiting room',
        tone: palette.caution,
        badgeCount: dashboard.waitingCount,
        onTap: () => context.go(Routes.schedule),
      ),
      QuickAction(
        icon: Icons.search,
        label: 'Find patient',
        tone: palette.info,
        onTap: () => context.go(Routes.patients),
      ),
    ];

    // Tile width decides this, not device class. A four-across row is too
    // cramped below roughly a 400dp phone, so the grid drops to two columns
    // rather than letting the labels clip; a wide window fits more than four
    // without stretching each tile into a banner.
    final columns = switch (context.breakpoint) {
      Breakpoint.expanded => 6,
      Breakpoint.medium => 4,
      Breakpoint.compact =>
        MediaQuery.sizeOf(context).width < 400 ? 2 : 4,
    };

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columns,
      mainAxisSpacing: m.spaceSm,
      crossAxisSpacing: m.spaceSm,
      // Fixed height rather than an aspect ratio: the tile content is a fixed
      // stack of icon and label, so tying height to width overflows on narrow
      // screens and leaves dead space on wide ones.
      mainAxisExtent: 116,
      children: actions,
    );
  }
}

/// Compact counts plus a week-at-a-glance bar chart.
///
/// Deliberately below the actionable sections: these numbers are context for
/// the day, not tasks, and putting them at the top would push the work down.
class _AtAGlance extends StatelessWidget {
  const _AtAGlance({required this.dashboard});

  final DashboardController dashboard;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceLg),
      child: SectionCard(
        title: 'This week',
        leading: const Icon(Icons.insights_outlined, size: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: m.spaceSm,
              runSpacing: m.spaceSm,
              children: <Widget>[
                _Stat(
                  label: 'Unsigned',
                  value: '${dashboard.draftNoteCount}',
                  tone: dashboard.draftNoteCount > 0
                      ? palette.caution
                      : palette.normal,
                  explanation: MetricExplanation(
                    title: 'Unsigned notes',
                    summary: 'Notes that have been started but not signed, '
                        'across every patient and every day — not just today.',
                    method: const <String>[
                      'Every clinical note in the database is counted whose '
                          'status is still draft.',
                      'A note becomes signed only when a clinician signs it, '
                          'which locks it and makes it the final record.',
                      'There is no time limit on this count: an unsigned note '
                          'from three weeks ago is still an unfinished record, '
                          'and hiding it after a day would be the opposite of '
                          'useful.',
                    ],
                    total: '${dashboard.draftNoteCount} unsigned',
                    caveat: 'An empty note that was opened and abandoned '
                        'counts here too. Opening it and signing or discarding '
                        'it is what clears it.',
                  ),
                ),
                _Stat(
                  label: 'Seen today',
                  value: '${dashboard.todayEncounterCount}',
                  tone: palette.primary,
                  explanation: MetricExplanation(
                    title: 'Seen today',
                    summary: 'Encounters started today at the active clinic.',
                    method: const <String>[
                      'Counts encounters whose start time falls between '
                          'midnight this morning and midnight tonight.',
                      'Filtered to the clinic currently selected at the top of '
                          'this screen — switching clinic changes this number.',
                      'It counts encounters, not patients: someone seen twice '
                          'in a day counts twice.',
                      'Status is not considered, so a visit still in progress '
                          'is already included.',
                    ],
                    total: '${dashboard.todayEncounterCount} today',
                  ),
                ),
                _Stat(
                  label: 'Observations',
                  value: '${dashboard.todayVitalsCount}',
                  tone: palette.accent,
                  explanation: MetricExplanation(
                    title: 'Observation sets today',
                    summary: 'Sets of vital signs recorded today, across all '
                        'clinics.',
                    method: const <String>[
                      'Counts rows of recorded observations with today’s date.',
                      'One set is one visit to the bedside, however many '
                          'individual values it contains — a blood pressure '
                          'and a temperature taken together are one set.',
                      'Unlike "seen today" this is not filtered by clinic.',
                    ],
                    total: '${dashboard.todayVitalsCount} sets',
                  ),
                ),
                _Stat(
                  label: 'Patients',
                  value: '${dashboard.patientCount}',
                  tone: palette.onSurfaceMuted,
                  explanation: MetricExplanation(
                    title: 'Registered patients',
                    summary: 'Everyone on this device’s register, ever.',
                    method: const <String>[
                      'Counts every patient record that has not been deleted.',
                      'It is a total, not an activity measure: it does not '
                          'shrink when someone stops attending, and it counts '
                          'patients registered at any clinic.',
                      'Any duplicate records that exist are counted twice — '
                          'the duplicate check on registration is what keeps '
                          'that number honest.',
                    ],
                    total: '${dashboard.patientCount} records',
                  ),
                ),
              ],
            ),
            if (dashboard.weekActivity.isNotEmpty) ...<Widget>[
              SizedBox(height: m.spaceLg),
              Row(
                children: <Widget>[
                  Text('Encounters per day', style: context.texts.labelSmall),
                  InfoDot(
                    explanation: MetricExplanation(
                      title: 'Encounters per day',
                      summary: 'How many encounters were started on each of '
                          'the last seven days, oldest on the left.',
                      method: const <String>[
                        'Each bar counts encounters started on that calendar '
                            'day, across every clinic.',
                        'The seven days end with today, so today’s bar is '
                            'still filling and will almost always look short.',
                        'Bars are scaled to the busiest day in the window, so '
                            'the tallest bar is always full height — the shape '
                            'shows relative load, not an absolute count.',
                        'The letters are weekday initials, which is why two '
                            'of them are T and two are S.',
                      ],
                      confidence: ExplainConfidence.measured,
                      caveat: 'Seven days is enough to see whether this week '
                          'is busier than usual. It is not enough to read a '
                          'trend from, and it is not analytics.',
                    ),
                  ),
                ],
              ),
              SizedBox(height: m.spaceSm),
              MiniBarChart(bars: dashboard.weekActivity),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.tone,
    this.explanation,
  });

  final String label;
  final String value;
  final Color tone;

  /// What exactly is being counted. A four-word label cannot distinguish
  /// "encounters started today at this clinic" from "patients seen today
  /// anywhere", and the difference is the whole meaning of the number.
  final MetricExplanation? explanation;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: m.spaceMd,
        vertical: m.spaceSm,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            style: context.texts.titleMedium?.copyWith(
              color: tone,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(width: m.spaceXs + 2),
          Text(label, style: context.texts.labelSmall),
          if (explanation case final explanation?)
            InfoDot(
              explanation: explanation,
              semanticLabel: 'What "$label" counts',
            ),
        ],
      ),
    );
  }
}

class _TodaySchedule extends StatelessWidget {
  const _TodaySchedule({required this.dashboard});

  final DashboardController dashboard;

  @override
  Widget build(BuildContext context) {
    if (dashboard.todaySchedule.isEmpty) return const SizedBox.shrink();

    final m = context.metrics;
    final upcoming = dashboard.todaySchedule
        .where((i) => !i.appointment.status.isFinished)
        .take(4)
        .toList();
    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceLg),
      child: SectionCard(
        title: "Today's clinic",
        subtitle: '${dashboard.remainingToday} still to see',
        leading: const Icon(Icons.event_outlined, size: 20),
        trailing: TextButton(
          onPressed: () => context.go(Routes.schedule),
          child: const Text('All'),
        ),
        child: Column(
          children: <Widget>[
            for (final item in upcoming)
              Padding(
                padding: EdgeInsets.only(bottom: m.spaceSm),
                child: AppointmentTile(
                  appointment: item.appointment,
                  patient: item.patient,
                  onTap: () => context.go(Routes.schedule),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Patients whose observations today scored medium or high on NEWS2.
///
/// Hidden entirely when empty — an always-present "nothing to see" card trains
/// people to stop looking at the place where warnings appear.
class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({required this.dashboard});

  final DashboardController dashboard;

  @override
  Widget build(BuildContext context) {
    if (dashboard.flagged.isEmpty) return const SizedBox.shrink();

    final m = context.metrics;
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceLg),
      child: Container(
        decoration: BoxDecoration(
          color: palette.criticalSubtle,
          borderRadius: BorderRadius.circular(m.radiusMd),
        ),
        padding: EdgeInsets.all(m.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.priority_high, color: palette.critical, size: 20),
                SizedBox(width: m.spaceSm),
                Expanded(
                  child: Text(
                    'Needs a second look',
                    style: context.texts.titleMedium
                        ?.copyWith(color: palette.critical),
                  ),
                ),
                InfoDot(
                  explanation: MetricExplanation(
                    title: 'Needs a second look',
                    summary: 'Patients whose observations today produced an '
                        'elevated early warning score.',
                    method: const <String>[
                      'Only observation sets recorded today are considered.',
                      'A set qualifies when its NEWS2 score reached the medium '
                          'or high band, or when any single parameter scored '
                          '3 on its own.',
                      'One row per patient — their highest-scoring set. Six '
                          'rows for the same person would bury everyone else.',
                      'Patients NEWS2 cannot score — under 16, or pregnant, or '
                          'with an incomplete observation set — never appear '
                          'here, because no score was produced for them.',
                      'The whole section is hidden when it is empty, rather '
                          'than showing "nothing to see". A panel that is '
                          'usually empty is one people stop looking at.',
                    ],
                    confidence: ExplainConfidence.validated,
                    source: 'Royal College of Physicians, NEWS2 (2017)',
                    caveat: 'Absence from this list is not reassurance. A '
                        'patient with no observations recorded today cannot '
                        'appear here, and neither can a child or a pregnant '
                        'patient however unwell they are.',
                  ),
                ),
              ],
            ),
            SizedBox(height: m.spaceXs),
            Text(
              'Elevated early warning score recorded today',
              style: context.texts.bodySmall,
            ),
            SizedBox(height: m.spaceSm),
            for (final item in dashboard.flagged)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => context.push(Routes.chartFor(item.patient.id)),
                leading: PatientAvatar(
                  initials: item.patient.initials,
                  seed: item.patient.id,
                  radius: 18,
                ),
                title: Text(
                  item.patient.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${item.patient.identityLine} · '
                  '${Fmt.time(item.vitals.recordedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: StatusPill(
                  label: 'NEWS ${item.vitals.news2Score}',
                  tone: News2Risk.values
                              .where((r) => r.name == item.vitals.news2Risk)
                              .firstOrNull ==
                          News2Risk.high
                      ? PillTone.critical
                      : PillTone.caution,
                  dense: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OpenWork extends StatelessWidget {
  const _OpenWork({required this.dashboard, required this.onChanged});

  final DashboardController dashboard;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    if (dashboard.openWork.isEmpty && dashboard.draftNoteCount == 0) {
      return const SizedBox.shrink();
    }

    final m = context.metrics;

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceLg),
      child: SectionCard(
        title: 'Unfinished charting',
        subtitle: '${dashboard.openWork.length} encounter'
            '${dashboard.openWork.length == 1 ? '' : 's'} to complete',
        leading: const Icon(Icons.edit_note, size: 20),
        child: dashboard.openWork.isEmpty
            ? const EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Nothing outstanding',
                compact: true,
              )
            : Column(
                children: dashboard.openWork.take(6).map((item) {
                  final sections = item.note?.filledSectionCount ?? 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () async {
                      await context.push(Routes.encounterFor(item.encounter.id));
                      await onChanged();
                    },
                    leading: PatientAvatar(
                      initials: item.patient.initials,
                      seed: item.patient.id,
                      radius: 18,
                    ),
                    title: Text(
                      item.patient.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.encounter.type.label} · '
                      '${Fmt.relative(item.encounter.startedAt)}'
                      '${sections > 0 ? ' · $sections/4' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: StatusPill(
                      label: item.encounter.status.label,
                      tone: item.encounter.status == EncounterStatus.completed
                          ? PillTone.info
                          : PillTone.caution,
                      dense: true,
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }
}

class _RecentPatients extends StatelessWidget {
  const _RecentPatients({required this.dashboard});

  final DashboardController dashboard;

  @override
  Widget build(BuildContext context) {
    if (dashboard.recentPatients.isEmpty) {
      return SectionCard(
        title: 'Get started',
        leading: const Icon(Icons.waving_hand_outlined, size: 20),
        child: EmptyState(
          icon: Icons.person_add_alt,
          title: 'No patients yet',
          message: 'Register a patient to begin, or load demo data from '
              'Settings to explore the app.',
          actionLabel: 'Register patient',
          onAction: () => context.push(Routes.patientNew),
          compact: true,
        ),
      );
    }

    return SectionCard(
      title: 'Recent patients',
      leading: const Icon(Icons.history, size: 20),
      trailing: TextButton(
        onPressed: () => context.go(Routes.patients),
        child: const Text('All'),
      ),
      child: Column(
        children: dashboard.recentPatients.take(6).map((patient) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => context.push(Routes.chartFor(patient.id)),
            leading: PatientAvatar(
              initials: patient.initials,
              seed: patient.id,
              radius: 18,
              badge: patient.allergyStatus == AllergyStatus.hasAllergies
                  ? AvatarBadge(
                      icon: Icons.priority_high,
                      tone: context.palette.critical,
                    )
                  : null,
            ),
            title: Text(
              patient.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              patient.identityLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              Fmt.relative(patient.lastSeenAt),
              style: context.texts.labelSmall,
            ),
          );
        }).toList(),
      ),
    );
  }
}
