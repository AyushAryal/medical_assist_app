/// Statistics that survive bad data.
///
/// Both places this app fits a line are looking at clinical measurements, and
/// clinical measurements contain mistakes: a cuff on the wrong arm, a
/// temperature taken straight after a hot drink, a clinic closed for a week.
/// The ordinary estimators are the ones that break on exactly that, so the
/// robust versions live here rather than being re-derived at each call site —
/// they were, and the two copies had already drifted on how ties are broken.
abstract final class RobustStats {
  /// The middle value, interpolating between the two middles of an even list.
  ///
  /// The input is sorted in place, which is what every caller wants anyway.
  static double median(List<double> values) {
    if (values.isEmpty) return 0;
    values.sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }

  /// Theil–Sen: the median of the slopes between every pair of points.
  ///
  /// Least squares is the obvious choice and the wrong one here. It is pulled
  /// hard by a single outlier, and one bad reading must not manufacture a
  /// deterioration warning or invert a reported trend. Theil–Sen tolerates up
  /// to about 29% corrupted points before its estimate breaks down, which is
  /// the property this needs.
  ///
  /// Pairs closer together than [minimumSpan] on the x axis are skipped: two
  /// observations in the same minute say nothing about a daily rate, and
  /// dividing by that interval produces an enormous slope from nothing.
  static double theilSenSlope(
    List<({double x, double y})> points, {
    double minimumSpan = 0,
  }) {
    final slopes = <double>[];
    for (var i = 0; i < points.length - 1; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final run = points[j].x - points[i].x;
        if (run.abs() <= minimumSpan) continue;
        slopes.add((points[j].y - points[i].y) / run);
      }
    }
    return slopes.isEmpty ? 0 : median(slopes);
  }
}
