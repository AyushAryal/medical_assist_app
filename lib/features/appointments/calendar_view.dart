import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../data/models/appointment.dart';

/// How much of the schedule is on screen at once.
enum CalendarScale { day, week, month }

extension CalendarScaleX on CalendarScale {
  String get label => switch (this) {
        CalendarScale.day => 'Day',
        CalendarScale.week => 'Week',
        CalendarScale.month => 'Month',
      };

  IconData get icon => switch (this) {
        CalendarScale.day => Icons.view_day_outlined,
        CalendarScale.week => Icons.view_week_outlined,
        CalendarScale.month => Icons.calendar_month_outlined,
      };
}

/// What one day in the grid needs to draw itself.
class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.booked,
    required this.waiting,
    required this.finished,
  });

  final DateTime date;

  /// Appointments that have not reached a terminal status.
  final int booked;

  /// Checked in and still waiting.
  final int waiting;
  final int finished;

  int get total => booked + finished;
  bool get isEmpty => total == 0;
}

/// A month grid.
///
/// Load, not detail. The question a clinician asks a month view is "which days
/// are heavy and which are free", and a grid of appointment titles at this size
/// answers neither — the cells are too small to read and too crowded to scan.
/// So each day shows a count and a density bar, and tapping it moves the day
/// list, which is where detail belongs.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  /// Any date within the month to display.
  final DateTime month;
  final Map<DateTime, CalendarDay> days;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  static DateTime dayKey(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // DateTime.weekday is 1 = Monday, and the grid starts on Monday.
    final leadingBlanks = first.weekday - 1;

    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _DayCell(
          date: DateTime(month.year, month.month, day),
          day: days[DateTime(month.year, month.month, day)],
          isSelected: dayKey(selected) ==
              DateTime(month.year, month.month, day),
          onTap: onSelect,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final label in _weekdayInitials)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: context.texts.labelSmall?.copyWith(
                      color: palette.onSurfaceMuted,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: m.spaceXs),
        GridView.count(
          shrinkWrap: true,
          // Explicitly zero, or the grid inherits the ambient safe-area
          // insets as padding and opens a dead band around the month.
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 7,
          mainAxisSpacing: m.spaceXs,
          crossAxisSpacing: m.spaceXs,
          // Near-square: the cell holds a plain number circle and a dot strip.
          childAspectRatio: 1.05,
          children: cells,
        ),
      ],
    );
  }

  /// Two Ts and two Ss, as every calendar has ever had.
  static const List<String> _weekdayInitials = <String>[
    'M', 'T', 'W', 'T', 'F', 'S', 'S',
  ];
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.day,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final CalendarDay? day;
  final bool isSelected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final isPast = date.isBefore(DateTime(now.year, now.month, now.day));

    // The family day cell: a plain number, a filled circle when chosen, a
    // soft circle on today, marker dots for load. No boxes, no dashes.
    return InkWell(
      onTap: () => onTap(date),
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _DayNumber(
            date: date,
            isSelected: isSelected,
            isToday: isToday,
            isPast: isPast,
          ),
          SizedBox(height: context.metrics.spaceXs / 2),
          _MarkerDots(day: day),
        ],
      ),
    );
  }
}

/// The day-of-month figure, drawn the family way: bare on the card surface,
/// a filled primary circle when it is the selected day, a soft primary
/// circle when it is today.
class _DayNumber extends StatelessWidget {
  const _DayNumber({
    required this.date,
    required this.isSelected,
    required this.isToday,
    required this.isPast,
    this.diameter = 32,
  });

  final DateTime date;
  final bool isSelected;
  final bool isToday;
  final bool isPast;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: isSelected
          ? BoxDecoration(color: palette.primary, shape: BoxShape.circle)
          : isToday
              ? BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                )
              : null,
      child: Text(
        '${date.day}',
        style: context.texts.labelLarge?.copyWith(
          color: isSelected
              ? palette.onPrimary
              : isToday
                  ? palette.primary
                  : isPast
                      ? palette.onSurfaceMuted
                      : palette.onSurface,
          fontWeight: isSelected || isToday ? FontWeight.w700 : null,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The family's load marker: up to three small dots under the number — the
/// language every OptERP calendar speaks. Caution-toned while anyone on that
/// day is still waiting, accent otherwise. A fixed-height strip so rows with
/// and without bookings keep the same rhythm.
class _MarkerDots extends StatelessWidget {
  const _MarkerDots({required this.day});

  final CalendarDay? day;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = day?.total ?? 0;
    final tone = (day?.waiting ?? 0) > 0 ? palette.caution : palette.accent;
    final count = total.clamp(0, 3);

    return SizedBox(
      height: 5,
      child: count == 0
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var i = 0; i < count; i++)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration:
                        BoxDecoration(color: tone, shape: BoxShape.circle),
                  ),
              ],
            ),
    );
  }
}

/// Seven days across, with the same density language as the month grid.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.weekStart,
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  final DateTime weekStart;
  final Map<DateTime, CalendarDay> days;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  /// The Monday of the week containing [date].
  static DateTime startOfWeek(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Row(
      children: <Widget>[
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: m.spaceXs / 2),
              child: _WeekDayCell(
                date: weekStart.add(Duration(days: i)),
                day: days[MonthGrid.dayKey(weekStart.add(Duration(days: i)))],
                isSelected: MonthGrid.dayKey(selected) ==
                    MonthGrid.dayKey(weekStart.add(Duration(days: i))),
                onTap: onSelect,
              ),
            ),
          ),
      ],
    );
  }
}

class _WeekDayCell extends StatelessWidget {
  const _WeekDayCell({
    required this.date,
    required this.day,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final CalendarDay? day;
  final bool isSelected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final isPast = date.isBefore(DateTime(now.year, now.month, now.day));

    // Same family cell as the month grid, with the weekday initial above it —
    // a muted letter and a plain number, not a boxed tile.
    return InkWell(
      onTap: () => onTap(date),
      customBorder: const StadiumBorder(),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: m.spaceXs),
        child: Column(
          children: <Widget>[
            Text(
              MonthGrid._weekdayInitials[date.weekday - 1],
              style: context.texts.labelSmall?.copyWith(
                color: palette.onSurfaceMuted,
                letterSpacing: 0.6,
              ),
            ),
            SizedBox(height: m.spaceXs),
            _DayNumber(
              date: date,
              isSelected: isSelected,
              isToday: isToday,
              isPast: isPast,
              diameter: 34,
            ),
            SizedBox(height: m.spaceXs / 2),
            _MarkerDots(day: day),
          ],
        ),
      ),
    );
  }
}

/// Folds a list of appointments into per-day counts.
Map<DateTime, CalendarDay> summariseByDay(List<Appointment> appointments) {
  final byDay = <DateTime, List<Appointment>>{};
  for (final appointment in appointments) {
    byDay
        .putIfAbsent(MonthGrid.dayKey(appointment.scheduledAt), () => <Appointment>[])
        .add(appointment);
  }

  return <DateTime, CalendarDay>{
    for (final entry in byDay.entries)
      entry.key: CalendarDay(
        date: entry.key,
        booked: entry.value.where((a) => !a.status.isFinished).length,
        waiting: entry.value.where((a) => a.status.isWaiting).length,
        finished: entry.value.where((a) => a.status.isFinished).length,
      ),
  };
}
