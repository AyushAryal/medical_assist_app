import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../clinical/insights/schedule_insights.dart';
import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../../core/routing/app_router.dart';
import '../../core/session/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/appointment.dart';
import '../../data/models/patient.dart';
import '../../data/repositories/clinical_repository.dart';
import 'appointment_tile.dart';
import 'calendar_view.dart';

typedef ScheduleRow = ({
  Appointment appointment,
  Patient patient,
  WaitEstimate? wait,
});

/// The clinic schedule: a calendar to navigate it, and a day list to work it.
///
/// The two halves answer different questions and both are needed. The calendar
/// answers "when is there room" and "how heavy is Thursday", which is what
/// booking a follow-up requires. The day list answers "who is here and what do
/// I do next", which is what running a clinic requires. On a tablet they sit
/// side by side, because moving between them is the whole task; on a phone the
/// calendar collapses to a week strip that keeps the day list in view.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _day = DateTime.now();
  CalendarScale _scale = CalendarScale.week;

  List<ScheduleRow> _rows = const <ScheduleRow>[];
  Map<DateTime, CalendarDay> _calendar = const <DateTime, CalendarDay>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// The range the calendar needs, given the current scale.
  ///
  /// A month view loads the surrounding month plus padding, so flicking to the
  /// next month is instant and the leading/trailing week of the grid is not
  /// mysteriously empty.
  ({DateTime from, DateTime to}) get _range {
    switch (_scale) {
      case CalendarScale.month:
        return (
          from: DateTime(_day.year, _day.month - 1),
          to: DateTime(_day.year, _day.month + 2),
        );
      case CalendarScale.week:
        final start = WeekStrip.startOfWeek(_day);
        return (
          from: start.subtract(const Duration(days: 7)),
          to: start.add(const Duration(days: 14)),
        );
      case CalendarScale.day:
        return (
          from: _day.subtract(const Duration(days: 1)),
          to: _day.add(const Duration(days: 2)),
        );
    }
  }

  Future<void> _load() async {
    final repository = context.read<ClinicalRepository>();
    final session = context.read<SessionController>();
    final assist = context.read<AppBootstrap>().assist;
    final clinicId = session.activeClinic?.id;

    final range = _range;
    final inRange = await repository.appointments.forRange(
      range.from,
      range.to,
      clinicId: clinicId,
    );

    final dayAppointments = await repository.appointments.forDay(
      _day,
      clinicId: clinicId,
    );

    // Consultation lengths from today's finished visits drive the wait
    // estimate — measured, not the booked slot length, because the booked
    // length is what somebody hoped for.
    final completed = dayAppointments
        .where((a) => a.status == AppointmentStatus.completed)
        .toList();

    final rows = <ScheduleRow>[];
    var ahead = 0;
    for (final appointment in dayAppointments) {
      final patient = await repository.patients.byId(appointment.patientId);
      if (patient == null) continue;

      final pending = !appointment.status.isFinished;
      rows.add((
        appointment: appointment,
        patient: patient,
        // Only for people actually still waiting, and only counting those in
        // front of them.
        wait: pending && ahead > 0
            ? assist.waitEstimate(
                aheadInQueue: ahead,
                completedToday: completed,
                visitType: appointment.type.name,
              )
            : null,
      ));
      if (pending) ahead++;
    }

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _calendar = summariseByDay(inRange);
      _loading = false;
    });
  }

  void _select(DateTime day) {
    setState(() => _day = day);
    _load();
  }

  void _shift(int units) {
    setState(() {
      _day = switch (_scale) {
        CalendarScale.day => _day.add(Duration(days: units)),
        CalendarScale.week => _day.add(Duration(days: 7 * units)),
        CalendarScale.month =>
          DateTime(_day.year, _day.month + units, _day.day),
      };
    });
    _load();
  }

  Future<void> _openActions(ScheduleRow row) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: PatientAvatar(
                initials: row.patient.initials,
                seed: row.patient.id,
                radius: 20,
              ),
              title: Text(row.patient.displayName),
              subtitle: Text(row.patient.identityLine),
            ),
            const Divider(height: 1),
            if (row.appointment.status == AppointmentStatus.scheduled ||
                row.appointment.status == AppointmentStatus.confirmed)
              ListTile(
                leading: const Icon(Icons.how_to_reg_outlined),
                title: const Text('Mark arrived'),
                subtitle: const Text('Patient has checked in'),
                onTap: () => Navigator.of(context).pop('arrived'),
              ),
            if (row.appointment.status.isOpen)
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Start visit'),
                subtitle: const Text('Opens a new encounter'),
                onTap: () => Navigator.of(context).pop('start'),
              ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Open chart'),
              onTap: () => Navigator.of(context).pop('chart'),
            ),
            if (!row.appointment.status.isFinished) ...<Widget>[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: const Text('Did not attend'),
                onTap: () => Navigator.of(context).pop('noshow'),
              ),
              ListTile(
                leading: const Icon(Icons.event_busy_outlined),
                title: const Text('Cancel appointment'),
                onTap: () => Navigator.of(context).pop('cancel'),
              ),
            ],
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;
    final repository = context.read<ClinicalRepository>();
    final session = context.read<SessionController>();

    switch (action) {
      case 'arrived':
        await repository.markArrived(row.appointment);
      case 'start':
        final encounter = await repository.startFromAppointment(
          row.appointment,
          providerName: session.signatureName,
        );
        if (mounted) await context.push(Routes.encounterFor(encounter.id));
      case 'chart':
        if (mounted) await context.push(Routes.chartFor(row.patient.id));
      case 'noshow':
        await repository.closeAppointment(
          row.appointment,
          AppointmentStatus.noShow,
        );
      case 'cancel':
        await repository.closeAppointment(
          row.appointment,
          AppointmentStatus.cancelled,
          reason: 'Cancelled from schedule',
        );
    }
    if (mounted) await _load();
  }

  bool get _isToday => _isSameDay(_day, DateTime.now());

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final wide = context.breakpoint.hasDetailPane;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Jump to today',
            icon: const Icon(Icons.today_outlined),
            onPressed: _isToday ? null : () => _select(DateTime.now()),
          ),
        ],
      ),
      body: wide
          // Calendar on the left, the day it selects on the right. Both stay
          // live, so working a clinic list never means leaving the calendar.
          ? TwoPane(
              masterFlex: 2,
              detailFlex: 3,
              minMasterWidth: 340,
              maxMasterWidth: 440,
              master: _calendarPane(context),
              detail: (context) => _dayPane(context, showDate: true),
            )
          // One column: the calendar is a fixed header and the day list scrolls
          // beneath it. Putting them in separate tabs would mean a mode switch
          // between choosing a day and working it, which is the same movement.
          : Column(
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    m.spaceLg,
                    m.spaceSm,
                    m.spaceLg,
                    0,
                  ),
                  child: _calendarPane(context),
                ),
                Expanded(child: _dayPane(context, showDate: false)),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(Routes.patients),
        icon: const Icon(Icons.person_search),
        label: const Text('Find patient'),
        backgroundColor: palette.primary,
      ),
    );
  }

  /// The calendar itself. On a tablet it owns the left pane and its own
  /// scroll; on a phone it is a fixed header above the day list.
  Widget _calendarPane(BuildContext context) {
    final m = context.metrics;
    final wide = context.breakpoint.hasDetailPane;

    final calendar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ScaleSwitcher(
          scale: _scale,
          onChanged: (scale) {
            setState(() => _scale = scale);
            _load();
          },
        ),
        SizedBox(height: m.spaceMd),
        _PeriodHeader(
          title: _periodTitle,
          subtitle: _periodSubtitle,
          onPrevious: () => _shift(-1),
          onNext: () => _shift(1),
        ),
        SizedBox(height: m.spaceMd),
        if (_scale == CalendarScale.month)
          MonthGrid(
            month: _day,
            days: _calendar,
            selected: _day,
            onSelect: _select,
          )
        else if (_scale == CalendarScale.week)
          WeekStrip(
            weekStart: WeekStrip.startOfWeek(_day),
            days: _calendar,
            selected: _day,
            onSelect: _select,
          ),
        SizedBox(height: m.spaceMd),
        _DayCounts(rows: _rows),
      ],
    );

    if (!wide) return calendar;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(m.spaceLg, m.spaceSm, m.spaceLg, m.spaceLg),
      child: calendar,
    );
  }

  Widget _dayPane(BuildContext context, {required bool showDate}) {
    final m = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showDate)
          Padding(
            padding: EdgeInsets.fromLTRB(m.spaceLg, m.spaceMd, m.spaceLg, 0),
            child: Text(
              _isToday ? 'Today · ${Fmt.date(_day)}' : Fmt.date(_day),
              style: context.texts.titleMedium,
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? EmptyState(
                      icon: Icons.event_available_outlined,
                      title: _isToday
                          ? 'Nothing booked today'
                          : 'Nothing booked on ${Fmt.dateShort(_day)}',
                      message: 'Book from a patient chart, or see a walk-in '
                          'without an appointment.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          m.spaceLg,
                          m.spaceMd,
                          m.spaceLg,
                          m.space2xl * 2,
                        ),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => SizedBox(height: m.spaceSm),
                        itemBuilder: (context, index) {
                          final row = _rows[index];
                          return AppointmentTile(
                            appointment: row.appointment,
                            patient: row.patient,
                            waitEstimate: row.wait,
                            onTap: () => _openActions(row),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  String get _periodTitle => switch (_scale) {
        CalendarScale.day =>
          _isToday ? 'Today' : Fmt.weekday(_day),
        CalendarScale.week => 'Week of ${Fmt.dateShort(
            WeekStrip.startOfWeek(_day),
          )}',
        CalendarScale.month => Fmt.monthAndYear(_day),
      };

  String get _periodSubtitle => switch (_scale) {
        CalendarScale.day => Fmt.date(_day),
        CalendarScale.week || CalendarScale.month => _isToday
            ? 'Showing today'
            : 'Showing ${Fmt.dateShort(_day)}',
      };

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// On a phone the calendar and the day list share one scroll view, so the day
/// list is always reachable without a mode switch.
class _ScaleSwitcher extends StatelessWidget {
  const _ScaleSwitcher({required this.scale, required this.onChanged});

  final CalendarScale scale;
  final ValueChanged<CalendarScale> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<CalendarScale>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: <ButtonSegment<CalendarScale>>[
        for (final value in CalendarScale.values)
          ButtonSegment<CalendarScale>(
            value: value,
            label: Text(value.label),
            icon: Icon(value.icon, size: 16),
          ),
      ],
      selected: <CalendarScale>{scale},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({
    required this.title,
    required this.subtitle,
    required this.onPrevious,
    required this.onNext,
  });

  final String title;
  final String subtitle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton.filledTonal(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrevious,
        ),
        Expanded(
          child: Column(
            children: <Widget>[
              Text(
                title,
                style: context.texts.titleMedium,
                textAlign: TextAlign.center,
              ),
              Text(
                subtitle,
                style: context.texts.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
        ),
      ],
    );
  }
}

class _DayCounts extends StatelessWidget {
  const _DayCounts({required this.rows});

  final List<ScheduleRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final m = context.metrics;
    final waiting = rows.where((r) => r.appointment.status.isWaiting).length;
    final remaining =
        rows.where((r) => !r.appointment.status.isFinished).length;

    return Wrap(
      spacing: m.spaceSm,
      runSpacing: m.spaceSm,
      children: <Widget>[
        StatusPill(
          label: '$remaining to see',
          tone: PillTone.info,
          icon: Icons.event_outlined,
          dense: true,
        ),
        if (waiting > 0)
          StatusPill(
            label: '$waiting waiting',
            tone: PillTone.caution,
            icon: Icons.chair_outlined,
            dense: true,
          ),
      ],
    );
  }
}
