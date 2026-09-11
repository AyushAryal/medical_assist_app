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
    final busiest = days.values.fold<int>(0, (max, d) => d.total > max ? d.total : max);

    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _DayCell(
          date: DateTime(month.year, month.month, day),
          day: days[DateTime(month.year, month.month, day)],
          isSelected: dayKey(selected) ==
              DateTime(month.year, month.month, day),
          busiest: busiest,
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
          // Slightly taller than square: the cell holds a date, a count and a
          // density bar, and a square cell clips the bar on a small phone.
          childAspectRatio: 0.82,
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
    required this.busiest,
    required this.onTap,
  });

  final DateTime date;
  final CalendarDay? day;
  final bool isSelected;
  final int busiest;
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
    final total = day?.total ?? 0;
    final waiting = day?.waiting ?? 0;

    return Material(
      color: isSelected
          ? palette.primaryContainer
          : total > 0
              ? palette.surfaceMuted
              : Colors.transparent,
      borderRadius: BorderRadius.circular(m.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(date),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: m.spaceXs),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(
                        color: isSelected ? palette.primary : palette.accent,
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Text(
                  '${date.day}',
                  style: context.texts.labelMedium?.copyWith(
                    color: isToday
                        ? palette.surface
                        : isSelected
                            ? palette.onPrimaryContainer
                            : isPast
                                ? palette.onSurfaceMuted
                                : palette.onSurface,
                    fontWeight:
                        isSelected || isToday ? FontWeight.w700 : null,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              SizedBox(height: m.spaceXs / 2),
              if (total == 0)
                // A dash, not an empty cell: it says "checked, nothing booked"
                // rather than leaving the reader to wonder if it failed to load.
                Text(
                  '·',
                  style: context.texts.labelSmall?.copyWith(
                    color: palette.onSurfaceMuted,
                  ),
                )
              else
                Column(
                  children: <Widget>[
                    // A count pill, not a muted digit: how loaded a day is
                    // must be readable at month-glance, per date.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 0.5,
                      ),
                      decoration: BoxDecoration(
                        color: (waiting > 0 ? palette.caution : palette.primary)
                            .withValues(alpha: context.isDark ? 0.28 : 0.14),
                        borderRadius: BorderRadius.circular(m.radiusSm),
                      ),
                      child: Text(
                        '$total',
                        style: context.texts.labelSmall?.copyWith(
                          color: waiting > 0 ? palette.caution : palette.primary,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: m.spaceXs / 2),
                    // Density bar. The track stays far lighter than any real
                    // bar so an empty day can never read as a full one.
                    _DensityBar(
                      fraction: busiest == 0 ? 0 : total / busiest,
                      tone: waiting > 0
                          ? palette.caution
                          : isPast
                              ? palette.outline
                              : palette.primary,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DensityBar extends StatelessWidget {
  const _DensityBar({required this.fraction, required this.tone});

  final double fraction;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return SizedBox(
      width: 20,
      height: 3,
      child: Stack(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: palette.outline.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(m.radiusXs / 2),
            ),
          ),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0.12, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(m.radiusXs / 2),
              ),
            ),
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
    final busiest =
        days.values.fold<int>(0, (max, d) => d.total > max ? d.total : max);

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
                busiest: busiest,
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
    required this.busiest,
    required this.onTap,
  });

  final DateTime date;
  final CalendarDay? day;
  final bool isSelected;
  final int busiest;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final total = day?.total ?? 0;

    return Material(
      color: isSelected ? palette.primaryContainer : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(m.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(date),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: m.spaceSm),
          child: Column(
            children: <Widget>[
              Text(
                MonthGrid._weekdayInitials[date.weekday - 1],
                style: context.texts.labelSmall,
              ),
              SizedBox(height: m.spaceXs / 2),
              Text(
                '${date.day}',
                style: context.texts.titleSmall?.copyWith(
                  color: isSelected
                      ? palette.onPrimaryContainer
                      : isToday
                          ? palette.accent
                          : palette.onSurface,
                  fontWeight: isSelected || isToday ? FontWeight.w700 : null,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              SizedBox(height: m.spaceXs),
              Text(
                total == 0 ? '—' : '$total',
                style: context.texts.labelSmall?.copyWith(
                  color: (day?.waiting ?? 0) > 0
                      ? palette.caution
                      : palette.onSurfaceMuted,
                  fontWeight: total == 0 ? null : FontWeight.w700,
                ),
              ),
              if (total > 0) ...<Widget>[
                SizedBox(height: m.spaceXs / 2),
                _DensityBar(
                  fraction: busiest == 0 ? 0 : total / busiest,
                  tone: (day?.waiting ?? 0) > 0
                      ? palette.caution
                      : palette.primary,
                ),
              ],
            ],
          ),
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
