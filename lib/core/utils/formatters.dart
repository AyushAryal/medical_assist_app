import 'package:intl/intl.dart';

/// Display formatting kept in one place so dates read identically everywhere.
///
/// Day-first with an alphabetic month (`14 Mar 2026`) is deliberate: `03/04`
/// is ambiguous between locales, and on a clinical record an ambiguous date is
/// a defect.
abstract final class Fmt {
  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _dateShort = DateFormat('d MMM');
  static final DateFormat _time = DateFormat('HH:mm');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, HH:mm');
  static final DateFormat _monthYear = DateFormat('MMMM y');
  static final DateFormat _weekday = DateFormat('EEEE, d MMMM');

  static String date(DateTime? value) => value == null ? '—' : _date.format(value);

  static String dateShort(DateTime? value) =>
      value == null ? '—' : _dateShort.format(value);

  /// 24-hour clock throughout — AM/PM slips are a documented source of drug
  /// timing errors.
  static String time(DateTime? value) => value == null ? '—' : _time.format(value);

  static String dateTime(DateTime? value) =>
      value == null ? '—' : _dateTime.format(value);

  static String weekday(DateTime value) => _weekday.format(value);

  /// `March 2026` — the heading a month calendar needs.
  static String monthAndYear(DateTime value) => _monthYear.format(value);

  /// Relative labels for recency lists. Falls back to an absolute date beyond
  /// a week, where "13 days ago" stops being easier to read than the date.
  static String relative(DateTime? value, {DateTime? now}) {
    if (value == null) return '—';
    final reference = now ?? DateTime.now();
    final diff = reference.difference(value);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24 && _isSameDay(value, reference)) {
      return 'Today ${_time.format(value)}';
    }
    if (_isSameDay(value, reference.subtract(const Duration(days: 1)))) {
      return 'Yesterday ${_time.format(value)}';
    }
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return _date.format(value);
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Trims trailing zeros so 37.0 shows as "37" but 37.5 keeps its decimal.
  static String number(num? value, {int decimals = 1}) {
    if (value == null) return '—';
    final text = value.toStringAsFixed(decimals);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  /// One statistic, rounded the way a reader expects and never over-precise.
  ///
  /// There were three of these — one in the chart painter, one in the handler
  /// that writes the headline, one in the renderer's detail rows — and they
  /// disagreed, so the same average appeared as `24`, `24.1` and `24.06` in
  /// three places on one screen. That is a small thing that makes a number
  /// look untrustworthy, which on a clinical figure is not a small thing.
  ///
  /// The rule: a whole number stays whole, anything large loses its decimal
  /// because at that magnitude it is noise, and NaN is a gap rather than a
  /// zero — a bucket with nothing in it must never read as a measurement of
  /// nothing.
  static String stat(double? value, {String? unit, String missing = '—'}) {
    if (value == null || value.isNaN) return missing;
    final rounded = value == value.roundToDouble() || value.abs() >= 100
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return unit == null || unit.isEmpty ? rounded : '$rounded $unit';
  }

  /// A stored code as a person reads it: `noShow` → `No show`.
  ///
  /// Enum names and database values are for code. Anywhere one reaches an axis
  /// label, a chip or a chart legend it goes through here first.
  static String sentence(String raw) {
    final spaced = raw
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
        .trim();
    if (spaced.isEmpty) return raw;
    return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
  }

  /// First letter up, the rest untouched — for a phrase that is already
  /// correctly cased, unlike [sentence] which lowercases the tail.
  static String titleCase(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  static String duration(Duration? value) {
    if (value == null) return '—';
    final hours = value.inHours;
    final minutes = value.inMinutes % 60;
    if (hours == 0) return '$minutes min';
    return '${hours}h ${minutes}m';
  }
}
