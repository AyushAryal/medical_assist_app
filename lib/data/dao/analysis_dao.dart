import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../ai/analytics/analysis.dart';
import '../../ai/schema/field_registry.dart';
import '../../core/db/app_database.dart';

/// The raw values one analysis needs, already narrowed to its columns.
typedef AnalysisRows = ({
  List<Map<String, Object?>> rows,
  bool truncated,
});

/// Reads the columns an [AnalysisSpec] names, and nothing else.
///
/// **No identifier in the statements below ever comes from what a person
/// typed.** A question selects entries from [FieldRegistry]; this reads
/// `DataTable.name` and `DataField.columns` off those entries. A phrase that
/// matches no registry entry produces no query at all, so the failure mode is
/// "I do not know that field" rather than a malformed or surprising statement.
/// Every value is bound as a parameter.
///
/// It returns rows rather than aggregates on purpose. The register on one
/// device is small, and one pass over the two or three columns an analysis
/// touches buys the median, the quartiles, the spread and the outliers that
/// separate SQL aggregates cannot give together — all of it computed in code
/// that is testable without a database.
class AnalysisDao {
  AnalysisDao(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  /// Above this the answer is a report to be exported, not a chart to be read.
  /// The caller is told when it bites, because a silently truncated chart is
  /// indistinguishable from a complete one.
  static const int maxRows = 20000;

  /// Column prefixes. Two, so a field named `status` on the subject table and
  /// one on `patients` cannot collide in the result map.
  static const String subjectPrefix = 's_';
  static const String patientPrefix = 'p_';

  Future<AnalysisRows> read(AnalysisSpec spec) async {
    final subject = spec.table;
    final columns = <String>{};
    final patientColumns = <String>{};

    void want(DataField? field, DataTable? owner) {
      if (field == null) return;
      final onPatients = owner != null &&
          owner.name == FieldRegistry.patients.name &&
          subject.name != FieldRegistry.patients.name;
      (onPatients ? patientColumns : columns).addAll(field.columns);
    }

    want(spec.measure, subject);
    want(spec.dimension, spec.dimensionTable ?? subject);
    want(spec.against, spec.againstTable ?? subject);
    for (final field in spec.patientFields) {
      want(field, FieldRegistry.patients);
    }

    // Always fetched: it is the axis every "over time" follow-up needs, and
    // fetching it once is cheaper than re-reading the table when someone taps
    // "per month".
    final time = subject.defaultTime;
    if (time != null) columns.addAll(time.columns);

    // Identity always rides along: the row's own id, and the patient it
    // belongs to where the table has one. Cheap — both are indexed columns
    // already in the page being read — and it is what lets a ranking put a
    // *person* behind a value instead of a bare number, and lets any future
    // "open the records behind this bar" do the same.
    columns.add('id');
    if (subject.patientColumn case final patientRef?) {
      columns.add(patientRef);
    }

    final needsPatients = patientColumns.isNotEmpty;
    final select = <String>[
      for (final column in columns) 's.$column AS $subjectPrefix$column',
      for (final column in patientColumns)
        'p.$column AS $patientPrefix$column',
    ].join(', ');

    final where = <String>[];
    final args = <Object?>[];

    if (subject.softDeleted) where.add('s.deleted_at IS NULL');
    if (needsPatients) where.add('p.deleted_at IS NULL');

    if (time != null && (spec.periodFrom != null || spec.periodTo != null)) {
      final column = 's.${time.columns.first}';
      if (spec.periodFrom != null) {
        where.add('$column >= ?');
        args.add(spec.periodFrom!.millisecondsSinceEpoch);
      }
      if (spec.periodTo != null) {
        where.add('$column < ?');
        args.add(spec.periodTo!.millisecondsSinceEpoch);
      }
    }

    final join = needsPatients
        ? 'JOIN patients p ON p.id = s.${subject.patientColumn}'
        : '';

    final rows = await _db.rawQuery(
      'SELECT $select FROM ${subject.name} s $join '
      'WHERE ${where.join(' AND ')} '
      'LIMIT ${maxRows + 1}',
      args,
    );

    return (
      rows: rows.length > maxRows ? rows.sublist(0, maxRows) : rows,
      truncated: rows.length > maxRows,
    );
  }
}
