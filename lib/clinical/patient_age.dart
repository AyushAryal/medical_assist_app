/// Age arithmetic used by the age-banded vital-sign reference ranges.
///
/// Paediatric vitals change fast enough that months matter under two years,
/// so age is carried as (years, months, days) rather than a rounded year.
class PatientAge {
  const PatientAge({
    required this.years,
    required this.months,
    required this.days,
    required this.totalDays,
  });

  final int years;
  final int months;
  final int days;
  final int totalDays;

  int get totalMonths => years * 12 + months;
  bool get isNeonate => totalDays < 28;
  bool get isInfant => years < 1;
  bool get isChild => years < 16;
  bool get isAdult => years >= 16;

  static PatientAge? fromDateOfBirth(DateTime? dob, {DateTime? asOf}) {
    if (dob == null) return null;
    final now = asOf ?? DateTime.now();
    final birth = DateTime(dob.year, dob.month, dob.day);
    final today = DateTime(now.year, now.month, now.day);
    if (birth.isAfter(today)) return null;

    var years = today.year - birth.year;
    var months = today.month - birth.month;
    var days = today.day - birth.day;

    if (days < 0) {
      months -= 1;
      // Days in the month preceding `today`.
      days += DateTime(today.year, today.month, 0).day;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }

    return PatientAge(
      years: years,
      months: months,
      days: days,
      totalDays: today.difference(birth).inDays,
    );
  }

  /// Clinical shorthand: days for neonates, months for infants, years after.
  String get label {
    if (totalDays < 28) return '$totalDays d';
    if (years < 1) return '$totalMonths mo';
    if (years < 2) return '${years}y ${months}m';
    return '${years}y';
  }

  @override
  String toString() => label;
}
