import 'dart:math' as math;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../ai/cohort/cohort_query.dart';
import '../../clinical/insights/note_intelligence.dart';
import '../../core/db/app_database.dart';
import '../../core/db/db_types.dart';
import '../models/patient.dart';

/// One row of a cohort result: the patient, plus why they matched.
typedef CohortRow = ({Patient patient, String? detail, DateTime? lastSeen});

/// A patient whose notes mention a term, with the text that matched.
///
/// The excerpt is the whole point: it is what lets "father takes warfarin" be
/// dismissed without opening the chart, and it is why this can be offered at
/// all rather than being too noisy to show.
typedef TextMention = ({
  Patient patient,
  String field,
  String excerpt,
  DateTime? at,
});

/// Answers a [CohortQuery] against the register.
///
/// **Every statement in this file is hand-written and covered by tests, and
/// nothing here is ever assembled from model output.** A language model may
/// choose which [CohortQuery] to run; the SQL that runs is always one of the
/// statements below. That is the difference between a wrong answer being
/// visible — the filters shown alongside the result do not match what was
/// asked — and a wrong answer being undetectable.
///
/// Every value is bound as a parameter. Nothing is interpolated into SQL, so
/// even a filter string that came from somewhere unexpected cannot change the
/// shape of the query.
class CohortDao {
  CohortDao(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  /// Patients matching [query], newest-seen first.
  ///
  /// [limit] is a guard rather than paging: a clinic-wide recall on a large
  /// register would otherwise build a list nobody can read, and the UI reports
  /// the true total separately so a truncated list is never mistaken for a
  /// complete one.
  Future<List<CohortRow>> patients(CohortQuery query, {int limit = 500}) async {
    final clause = _where(query);
    final rows = await _db.rawQuery(
      '''
      SELECT p.*
      FROM patients p
      WHERE ${clause.sql}
      ORDER BY ${query.mostRecent != null
          ? 'p.created_at DESC'
          : 'p.last_seen_at IS NULL DESC, p.last_seen_at DESC'}
      LIMIT ?
      ''',
      <Object?>[...clause.args, query.mostRecent ?? limit],
    );

    return rows.map((row) {
      final patient = Patient.fromMap(row);
      return (
        patient: patient,
        detail: null,
        lastSeen: patient.lastSeenAt,
      );
    }).toList(growable: false);
  }

  /// How many patients match, ignoring any display limit.
  Future<int> count(CohortQuery query) async {
    final clause = _where(query);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM patients p WHERE ${clause.sql}',
      clause.args,
    );
    final total = Sqflite.firstIntValue(rows) ?? 0;
    // "The latest ten" is ten, even where forty match — reporting the wider
    // number beside a deliberately short list invites the reader to think
    // something was hidden from them.
    return query.mostRecent == null
        ? total
        : math.min(total, query.mostRecent!);
  }

  /// How many *encounters* fall in the query's period — the activity question.
  ///
  /// Counts visits rather than people on purpose: "how many did we see last
  /// month" is a workload question, and someone seen three times is three
  /// consultations' worth of work.
  Future<int> encounterCount(CohortQuery query) async {
    final where = StringBuffer('e.deleted_at IS NULL');
    final args = <Object?>[];

    if (query.periodFrom != null) {
      where.write(' AND e.started_at >= ?');
      args.add(toEpoch(query.periodFrom!));
    }
    if (query.periodTo != null) {
      where.write(' AND e.started_at < ?');
      args.add(toEpoch(query.periodTo!));
    }
    if (query.clinicId != null) {
      where.write(' AND e.clinic_id = ?');
      args.add(query.clinicId);
    }
    if (query.visitType != null) {
      where.write(' AND e.type = ?');
      args.add(query.visitType);
    }

    // Patient-level filters still apply — "how many under-fives did we see"
    // is an encounter count restricted to a cohort.
    final patientClause = _where(query, alias: 'p2');
    if (patientClause.isFiltered) {
      where.write(
        ' AND EXISTS (SELECT 1 FROM patients p2 '
        'WHERE p2.id = e.patient_id AND ${patientClause.sql})',
      );
      args.addAll(patientClause.args);
    }

    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM encounters e WHERE $where',
      args,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Builds the patient-level WHERE clause.
  ///
  /// One function, so every entry point filters identically. A count and a list
  /// that disagree about who matches is worse than either being wrong alone —
  /// it destroys confidence in both.
  _Clause _where(CohortQuery query, {String alias = 'p'}) {
    final where = StringBuffer('$alias.deleted_at IS NULL');
    final args = <Object?>[];
    var filtered = false;

    if (!query.includeDeceased) {
      where.write(' AND $alias.deceased_date IS NULL');
    }

    if (query.nameStartsWith case final prefix?) {
      // Either name part: someone asking for "the Aryals" does not know or
      // care which field a clinic filed it under, and transposed name fields
      // are a routine data-entry error.
      where.write(
        ' AND (LOWER($alias.family_name) LIKE ? ESCAPE \'\\\' '
        'OR LOWER($alias.given_name) LIKE ? ESCAPE \'\\\')',
      );
      final pattern = '${_escapeLike(prefix.toLowerCase())}%';
      args..add(pattern)..add(pattern);
      filtered = true;
    }

    if (query.nameContains case final fragment?) {
      where.write(
        ' AND (LOWER($alias.family_name) LIKE ? ESCAPE \'\\\' '
        'OR LOWER($alias.given_name) LIKE ? ESCAPE \'\\\')',
      );
      final pattern = '%${_escapeLike(fragment.toLowerCase())}%';
      args..add(pattern)..add(pattern);
      filtered = true;
    }

    if (query.mrn case final mrn?) {
      where.write(' AND $alias.mrn = ?');
      args.add(mrn);
      filtered = true;
    }

    if (query.medication case final medication?) {
      // Prefix match, so "warfarin" finds "Warfarin 3mg". The escape below
      // matters: a drug name containing % or _ would otherwise become a
      // wildcard and silently over-match.
      where.write(
        ' AND EXISTS (SELECT 1 FROM medications m '
        "WHERE m.patient_id = $alias.id AND m.deleted_at IS NULL "
        "AND m.status = 'active' "
        "AND LOWER(m.name) LIKE ? ESCAPE '\\')",
      );
      args.add('${_escapeLike(medication.toLowerCase())}%');
      filtered = true;
    }

    if (query.problem case final problem?) {
      where.write(
        ' AND EXISTS (SELECT 1 FROM problems pr '
        "WHERE pr.patient_id = $alias.id AND pr.deleted_at IS NULL "
        "AND pr.status = 'active' "
        "AND LOWER(pr.display) LIKE ? ESCAPE '\\')",
      );
      args.add('%${_escapeLike(problem.toLowerCase())}%');
      filtered = true;
    }

    if (query.allergy case final allergy?) {
      where.write(
        ' AND EXISTS (SELECT 1 FROM allergies a '
        "WHERE a.patient_id = $alias.id AND a.deleted_at IS NULL "
        "AND a.status = 'active' "
        "AND LOWER(a.substance) LIKE ? ESCAPE '\\')",
      );
      args.add('${_escapeLike(allergy.toLowerCase())}%');
      filtered = true;
    }

    if (query.ageBand case final band?) {
      // Dates of birth are stored as ISO text, which sorts chronologically, so
      // the comparison is done on date strings rather than by computing an age
      // per row. A patient with no recorded date of birth cannot be placed in
      // a band and is excluded — stated in the explanation, because silently
      // dropping people from a recall list would be exactly the wrong
      // behaviour to leave undocumented.
      final now = DateTime.now();
      where.write(' AND $alias.date_of_birth IS NOT NULL');

      // Born on or before this date ⇒ at least minYears old.
      if (band.minYears > 0) {
        where.write(' AND $alias.date_of_birth <= ?');
        args.add(
          toIsoDate(DateTime(now.year - band.minYears, now.month, now.day)),
        );
      }
      // Born after this date ⇒ strictly younger than maxYears.
      if (band.maxYears case final maxYears?) {
        where.write(' AND $alias.date_of_birth > ?');
        args.add(
          toIsoDate(DateTime(now.year - maxYears, now.month, now.day)),
        );
      }
      filtered = true;
    }

    if (query.sexAtBirth case final sex?) {
      where.write(' AND $alias.sex_at_birth = ?');
      args.add(sex);
      filtered = true;
    }

    if (query.notSeenSince case final since?) {
      // NULL included deliberately: someone registered and never seen is
      // precisely who an overdue list should surface.
      where.write(' AND ($alias.last_seen_at IS NULL OR $alias.last_seen_at < ?)');
      args.add(toEpoch(since));
      filtered = true;
    }

    if (query.entity == QueryEntity.appointments &&
        (query.periodFrom != null || query.appointmentStatus != null)) {
      // An appointment filter on a *patient* query means "patients who have
      // such an appointment", which is a different question from "list the
      // appointments" and is answered by the same clause.
      final conditions = StringBuffer(
        'ap.patient_id = $alias.id AND ap.deleted_at IS NULL',
      );
      final inner = <Object?>[];
      if (query.periodFrom != null) {
        conditions.write(' AND ap.scheduled_at >= ?');
        inner.add(toEpoch(query.periodFrom!));
      }
      if (query.periodTo != null) {
        conditions.write(' AND ap.scheduled_at < ?');
        inner.add(toEpoch(query.periodTo!));
      }
      if (query.appointmentStatus != null) {
        conditions.write(' AND ap.status = ?');
        inner.add(query.appointmentStatus);
      }
      where.write(
        ' AND EXISTS (SELECT 1 FROM appointments ap WHERE $conditions)',
      );
      args.addAll(inner);
      filtered = true;
    } else if (query.periodFrom != null || query.periodTo != null) {
      final conditions = StringBuffer(
        'e.patient_id = $alias.id AND e.deleted_at IS NULL',
      );
      final inner = <Object?>[];
      if (query.periodFrom != null) {
        conditions.write(' AND e.started_at >= ?');
        inner.add(toEpoch(query.periodFrom!));
      }
      if (query.periodTo != null) {
        conditions.write(' AND e.started_at < ?');
        inner.add(toEpoch(query.periodTo!));
      }
      if (query.visitType != null) {
        conditions.write(' AND e.type = ?');
        inner.add(query.visitType);
      }
      where.write(
        ' AND EXISTS (SELECT 1 FROM encounters e WHERE $conditions)',
      );
      args.addAll(inner);
      filtered = true;
    }

    if (query.clinicId case final clinicId?) {
      where.write(' AND $alias.primary_clinic_id = ?');
      args.add(clinicId);
      filtered = true;
    }

    return _Clause(where.toString(), args, filtered);
  }

  /// How many appointments match — the booked-slot counterpart to
  /// [encounterCount].
  ///
  /// Kept separate because the two answer genuinely different questions:
  /// appointments count what was *booked*, encounters count what *happened*,
  /// and in a clinic with many non-attenders those numbers are far apart.
  /// Conflating them would quietly overstate activity.
  Future<int> appointmentCount(CohortQuery query) async {
    final clause = _appointmentWhere(query);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM appointments ap WHERE ${clause.sql}',
      clause.args,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// The appointments themselves, with the patient resolved.
  Future<List<CohortRow>> appointments(
    CohortQuery query, {
    int limit = 500,
  }) async {
    final clause = _appointmentWhere(query);
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, ap.scheduled_at AS ap_scheduled_at, ap.status AS ap_status
      FROM appointments ap
      JOIN patients p ON p.id = ap.patient_id
      WHERE ${clause.sql} AND p.deleted_at IS NULL
      ORDER BY ap.scheduled_at DESC
      LIMIT ?
      ''',
      <Object?>[...clause.args, limit],
    );

    return rows.map((row) {
      // The joined appointment columns are aliased so they cannot collide with
      // the patient columns `Patient.fromMap` reads.
      final scheduled = row['ap_scheduled_at'] as int?;
      return (
        patient: Patient.fromMap(row),
        detail: row['ap_status'] as String?,
        lastSeen: scheduled == null ? null : fromEpoch(scheduled),
      );
    }).toList(growable: false);
  }

  _Clause _appointmentWhere(CohortQuery query) {
    final where = StringBuffer('ap.deleted_at IS NULL');
    final args = <Object?>[];

    if (query.periodFrom != null) {
      where.write(' AND ap.scheduled_at >= ?');
      args.add(toEpoch(query.periodFrom!));
    }
    if (query.periodTo != null) {
      where.write(' AND ap.scheduled_at < ?');
      args.add(toEpoch(query.periodTo!));
    }
    if (query.appointmentStatus != null) {
      where.write(' AND ap.status = ?');
      args.add(query.appointmentStatus);
    }
    if (query.clinicId != null) {
      where.write(' AND ap.clinic_id = ?');
      args.add(query.clinicId);
    }

    // Patient-level filters still apply, so "diabetics with appointments this
    // week" works without a second code path.
    final patientClause = _where(
      // The appointment window is already applied above; re-applying it as a
      // patient filter would demand a *second* matching appointment.
      query.copyWith(
        clear: const <String>{'periodFrom', 'periodTo', 'appointmentStatus'},
      ),
      alias: 'p2',
    );
    if (patientClause.isFiltered) {
      where.write(
        ' AND EXISTS (SELECT 1 FROM patients p2 '
        'WHERE p2.id = ap.patient_id AND ${patientClause.sql})',
      );
      args.addAll(patientClause.args);
    }

    return _Clause(where.toString(), args, true);
  }

  /// Observation sets matching the query.
  ///
  /// Reaching the vitals table is what lets a deterioration sweep be asked
  /// directly — "everything that scored 5 or more this week" — rather than
  /// only being surfaced on the day it happened, which is all the dashboard
  /// can do.
  Future<int> vitalsCount(CohortQuery query) async {
    final clause = _vitalsWhere(query);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM vitals v WHERE ${clause.sql}',
      clause.args,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<List<CohortRow>> vitals(CohortQuery query, {int limit = 500}) async {
    final clause = _vitalsWhere(query);
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, v.recorded_at AS v_at, v.news2_score AS v_score,
             v.systolic_bp AS v_sys, v.diastolic_bp AS v_dia
      FROM vitals v
      JOIN patients p ON p.id = v.patient_id
      WHERE ${clause.sql} AND p.deleted_at IS NULL
      ORDER BY v.recorded_at DESC
      LIMIT ?
      ''',
      <Object?>[...clause.args, limit],
    );

    return rows.map((row) {
      final score = row['v_score'] as int?;
      final systolic = row['v_sys'] as int?;
      final diastolic = row['v_dia'] as int?;
      return (
        patient: Patient.fromMap(row),
        detail: <String>[
          if (score != null) 'NEWS2 $score',
          if (systolic != null && diastolic != null) '$systolic/$diastolic',
        ].join(' · '),
        lastSeen: fromEpochOrNull(row['v_at'] as int?),
      );
    }).toList(growable: false);
  }

  _Clause _vitalsWhere(CohortQuery query) {
    final where = StringBuffer('v.deleted_at IS NULL');
    final args = <Object?>[];

    if (query.periodFrom != null) {
      where.write(' AND v.recorded_at >= ?');
      args.add(toEpoch(query.periodFrom!));
    }
    if (query.periodTo != null) {
      where.write(' AND v.recorded_at < ?');
      args.add(toEpoch(query.periodTo!));
    }
    if (query.news2AtLeast != null) {
      where.write(' AND v.news2_score >= ?');
      args.add(query.news2AtLeast);
    }
    if (query.systolicAtLeast != null) {
      where.write(' AND v.systolic_bp >= ?');
      args.add(query.systolicAtLeast);
    }
    if (query.abnormalOnly) {
      // Adult reference bounds, applied in SQL so the filter can run over the
      // whole table. Age-banded flagging is a per-row judgement the app makes
      // when it *displays* an observation, and is deliberately not duplicated
      // here — the explanation sheet says so, because a paediatric set that
      // this misses would otherwise be a silent omission.
      where.write(
        ' AND (v.systolic_bp >= 180 OR v.systolic_bp <= 90'
        ' OR v.heart_rate >= 130 OR v.heart_rate <= 40'
        ' OR v.respiratory_rate >= 25 OR v.respiratory_rate <= 8'
        ' OR v.spo2 <= 91 OR v.temperature_c >= 39 OR v.temperature_c <= 35'
        ' OR v.news2_score >= 5)',
      );
    }

    final patientClause = _where(
      query.copyWith(clear: const <String>{'periodFrom', 'periodTo'}),
      alias: 'p2',
    );
    if (patientClause.isFiltered) {
      where.write(
        ' AND EXISTS (SELECT 1 FROM patients p2 '
        'WHERE p2.id = v.patient_id AND ${patientClause.sql})',
      );
      args.addAll(patientClause.args);
    }

    return _Clause(where.toString(), args, true);
  }

  /// Clinical notes, including unsigned drafts.
  ///
  /// Unfinished charting is the one thing here with a deadline, and until now
  /// it was only a number on the dashboard with no way to ask *whose*.
  Future<int> noteCount(CohortQuery query) async {
    final clause = _noteWhere(query);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM clinical_notes n WHERE ${clause.sql}',
      clause.args,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<List<CohortRow>> notes(CohortQuery query, {int limit = 500}) async {
    final clause = _noteWhere(query);
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, n.status AS n_status, n.updated_at AS n_at
      FROM clinical_notes n
      JOIN patients p ON p.id = n.patient_id
      WHERE ${clause.sql} AND p.deleted_at IS NULL
      ORDER BY n.updated_at DESC
      LIMIT ?
      ''',
      <Object?>[...clause.args, limit],
    );

    return rows.map((row) {
      return (
        patient: Patient.fromMap(row),
        detail: row['n_status'] as String?,
        lastSeen: fromEpochOrNull(row['n_at'] as int?),
      );
    }).toList(growable: false);
  }

  _Clause _noteWhere(CohortQuery query) {
    final where = StringBuffer('n.deleted_at IS NULL');
    final args = <Object?>[];

    if (query.noteStatus != null) {
      where.write(' AND n.status = ?');
      args.add(query.noteStatus);
    }
    if (query.periodFrom != null) {
      where.write(' AND n.created_at >= ?');
      args.add(toEpoch(query.periodFrom!));
    }
    if (query.periodTo != null) {
      where.write(' AND n.created_at < ?');
      args.add(toEpoch(query.periodTo!));
    }

    final patientClause = _where(
      query.copyWith(clear: const <String>{'periodFrom', 'periodTo'}),
      alias: 'p2',
    );
    if (patientClause.isFiltered) {
      where.write(
        ' AND EXISTS (SELECT 1 FROM patients p2 '
        'WHERE p2.id = n.patient_id AND ${patientClause.sql})',
      );
      args.addAll(patientClause.args);
    }

    return _Clause(where.toString(), args, true);
  }

  /// Attached photos, documents and recordings.
  Future<int> fileCount(CohortQuery query) async {
    final clause = _fileWhere(query);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM attachments a WHERE ${clause.sql}',
      clause.args,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<List<CohortRow>> files(CohortQuery query, {int limit = 500}) async {
    final clause = _fileWhere(query);
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, a.kind AS a_kind, a.caption AS a_caption,
             a.created_at AS a_at
      FROM attachments a
      JOIN patients p ON p.id = a.patient_id
      WHERE ${clause.sql} AND p.deleted_at IS NULL
      ORDER BY a.created_at DESC
      LIMIT ?
      ''',
      <Object?>[...clause.args, limit],
    );

    return rows.map((row) {
      return (
        patient: Patient.fromMap(row),
        detail: (row['a_caption'] as String?) ?? (row['a_kind'] as String?),
        lastSeen: fromEpochOrNull(row['a_at'] as int?),
      );
    }).toList(growable: false);
  }

  _Clause _fileWhere(CohortQuery query) {
    final where = StringBuffer('a.deleted_at IS NULL');
    final args = <Object?>[];

    if (query.fileKind != null) {
      where.write(' AND a.kind = ?');
      args.add(query.fileKind);
    }
    if (query.periodFrom != null) {
      where.write(' AND a.created_at >= ?');
      args.add(toEpoch(query.periodFrom!));
    }
    if (query.periodTo != null) {
      where.write(' AND a.created_at < ?');
      args.add(toEpoch(query.periodTo!));
    }

    final patientClause = _where(
      query.copyWith(clear: const <String>{'periodFrom', 'periodTo'}),
      alias: 'p2',
    );
    if (patientClause.isFiltered) {
      where.write(
        ' AND EXISTS (SELECT 1 FROM patients p2 '
        'WHERE p2.id = a.patient_id AND ${patientClause.sql})',
      );
      args.addAll(patientClause.args);
    }

    return _Clause(where.toString(), args, true);
  }

  /// Patients whose *notes* mention a term, and who are not already on the
  /// structured result.
  ///
  /// This exists because of an asymmetry I originally got wrong. The structured
  /// filters were treated as though over-matching and under-matching were
  /// equally bad. For a recall list they are not: an extra patient to check
  /// costs a moment, and a **missed** patient on a warfarin recall is the exact
  /// harm the list was run to prevent. Clinical reality is that medication and
  /// problem lists drift out of date while the narrative stays rich, so the
  /// people most likely to be missed are exactly the ones only the notes know
  /// about.
  ///
  /// Two things keep this from becoming noise, and both are non-negotiable:
  ///
  /// * **Denials are dropped.** "No history of warfarin" must never place
  ///   someone on a warfarin list. The judgement is
  ///   [NoteIntelligence.isNegatedAt] — the same one the note extractor uses,
  ///   so there are not two answers to one question.
  /// * **The sentence comes with it.** A hit is shown with its surrounding
  ///   text, so "father takes warfarin" is dismissed at a glance. A bare name
  ///   on a secondary list would be worse than no list, because it would be
  ///   believed.
  ///
  /// The result is deliberately never merged into the count. It is weaker
  /// evidence and it is presented as weaker evidence.
  Future<List<TextMention>> mentions(
    String term, {
    Set<String> excludePatientIds = const <String>{},
    int limit = 40,
  }) =>
      mentionsAny(<String>[term],
          excludePatientIds: excludePatientIds, limit: limit);

  /// The same search across every prose field the record holds, for any of
  /// several terms.
  ///
  /// Widened from clinical notes alone because the original scope encoded an
  /// assumption that turned out to be wrong: that the useful words all live in
  /// the note body. They do not. A presenting complaint, the reason a visit was
  /// booked, why a medicine was started, what an allergic reaction looked like,
  /// the caption on a photograph — each is prose somebody typed, and each is
  /// somewhere a word like "coffee" legitimately appears.
  ///
  /// Any term matching is enough. "Coffee or tea" is one question, and a
  /// record mentioning either is worth showing when the excerpt comes with it.
  Future<List<TextMention>> mentionsAny(
    List<String> terms, {
    Set<String> excludePatientIds = const <String>{},
    int limit = 40,
  }) async {
    if (terms.isEmpty) return const <TextMention>[];
    // Only the first drives the SQL; the rest are matched in Dart over the
    // returned rows. Widening the query per term multiplies the scan across
    // tables that have no index for it, and the first term is the one the
    // reader led with.
    final term = terms.first;
    final pattern = '%${_escapeLike(term.toLowerCase())}%';

    // The note body and the presenting complaint. Both are free text a
    // clinician wrote; neither is indexed, so the scan is bounded by `limit`
    // and by the newest-first ordering.
    // Every prose field on the record, not just the note body. Each is text
    // somebody typed, and each is somewhere an ordinary word legitimately
    // appears. `UNION ALL` rather than a join across all of them: the tables
    // have no relationship to force, and one scan each is cheaper than the
    // cross product.
    final rows = await _db.rawQuery(
      '''
      SELECT * FROM (
        -- One branch per note section, so a hit is labelled with the section
        -- it was actually found in. Collapsing them with COALESCE picked the
        -- first non-null section rather than the matching one, and labelled
        -- every hit 'Assessment'.
        SELECT p.*, 'Subjective' AS src_field, n.subjective AS src_text,
               n.created_at AS src_at
        FROM clinical_notes n
        JOIN patients p ON p.id = n.patient_id
        WHERE n.deleted_at IS NULL
          AND LOWER(COALESCE(n.subjective, '')) LIKE ? ESCAPE '\\'

        UNION ALL
        SELECT p.*, 'Objective', n.objective, n.created_at
        FROM clinical_notes n
        JOIN patients p ON p.id = n.patient_id
        WHERE n.deleted_at IS NULL
          AND LOWER(COALESCE(n.objective, '')) LIKE ? ESCAPE '\\'

        UNION ALL
        SELECT p.*, 'Assessment', n.assessment, n.created_at
        FROM clinical_notes n
        JOIN patients p ON p.id = n.patient_id
        WHERE n.deleted_at IS NULL
          AND LOWER(COALESCE(n.assessment, '')) LIKE ? ESCAPE '\\'

        UNION ALL
        SELECT p.*, 'Plan', n.plan, n.created_at
        FROM clinical_notes n
        JOIN patients p ON p.id = n.patient_id
        WHERE n.deleted_at IS NULL
          AND LOWER(COALESCE(n.plan, '')) LIKE ? ESCAPE '\\'

        UNION ALL
        SELECT p.*, 'Presenting complaint', e.chief_complaint, e.started_at
        FROM encounters e
        JOIN patients p ON p.id = e.patient_id
        WHERE e.deleted_at IS NULL
          AND LOWER(COALESCE(e.chief_complaint, '')) LIKE ? ESCAPE '\\'

        UNION ALL
        SELECT p.*, 'Reason for appointment', ap.reason, ap.scheduled_at
        FROM appointments ap
        JOIN patients p ON p.id = ap.patient_id
        WHERE ap.deleted_at IS NULL
          AND LOWER(COALESCE(ap.reason, '')) LIKE ? ESCAPE '\\'

        UNION ALL
        SELECT p.*, 'Medication', md.indication, md.created_at
        FROM medications md
        JOIN patients p ON p.id = md.patient_id
        WHERE md.deleted_at IS NULL
          AND LOWER(COALESCE(md.indication, '')) LIKE ? ESCAPE '\\'

        UNION ALL
        SELECT p.*, 'Allergy reaction', al.reaction, al.created_at
        FROM allergies al
        JOIN patients p ON p.id = al.patient_id
        WHERE al.deleted_at IS NULL
          AND LOWER(COALESCE(al.reaction, '')) LIKE ? ESCAPE '\\'

        UNION ALL
        SELECT p.*, 'Problem note', pr.notes, pr.created_at
        FROM problems pr
        JOIN patients p ON p.id = pr.patient_id
        WHERE pr.deleted_at IS NULL
          AND LOWER(COALESCE(pr.notes, '')) LIKE ? ESCAPE '\\'

        UNION ALL
        SELECT p.*, 'Observation note', v.notes, v.recorded_at
        FROM vitals v
        JOIN patients p ON p.id = v.patient_id
        WHERE v.deleted_at IS NULL
          AND LOWER(COALESCE(v.notes, '')) LIKE ? ESCAPE '\\'

        UNION ALL
        SELECT p.*, 'File caption', a.caption, a.created_at
        FROM attachments a
        JOIN patients p ON p.id = a.patient_id
        WHERE a.deleted_at IS NULL
          AND LOWER(COALESCE(a.caption, '')) LIKE ? ESCAPE '\\'
      )
      WHERE deleted_at IS NULL AND deceased_date IS NULL
      ORDER BY src_at DESC
      LIMIT ?
      ''',
      <Object?>[
        // One bind per LIKE in the union above.
        for (var i = 0; i < 11; i++) pattern,
        limit * 4,
      ],
    );

    final out = <TextMention>[];
    final seen = <String>{};

    for (final row in rows) {
      final patientId = row['id'] as String;
      if (excludePatientIds.contains(patientId)) continue;
      // One mention per patient. Six hits for the same person buries everyone
      // else on a list whose whole purpose is finding who was left out.
      if (seen.contains(patientId)) continue;

      final text = row['src_text'] as String?;
      if (text == null) continue;

      // Any of the terms. The first drove the query; the rest are checked here
      // so "coffee or tea" is one question rather than two searches.
      final lower = text.toLowerCase();
      var index = -1;
      var matchedTerm = term;
      for (final candidate in terms) {
        final at = lower.indexOf(candidate.toLowerCase());
        if (at < 0) continue;
        index = at;
        matchedTerm = candidate;
        break;
      }
      if (index < 0) continue;
      // "No history of coffee" is not a coffee record.
      if (NoteIntelligence.isNegatedAt(text, index)) continue;

      seen.add(patientId);
      out.add((
        patient: Patient.fromMap(row),
        field: row['src_field'] as String? ?? 'Note',
        excerpt: _excerpt(text, index, matchedTerm.length),
        at: fromEpochOrNull(row['src_at'] as int?),
      ));
      if (out.length >= limit) break;
    }

    return out;
  }

  /// The sentence around a hit, so the reader can judge it without opening the
  /// chart.
  static String _excerpt(String text, int index, int termLength) {
    const window = 70;
    var start = index - window;
    var end = index + termLength + window;
    if (start < 0) start = 0;
    if (end > text.length) end = text.length;

    // Snap to whitespace so the excerpt does not begin or end mid-word.
    while (start > 0 && !RegExp(r'\s').hasMatch(text[start])) {
      start--;
    }
    while (end < text.length && !RegExp(r'\s').hasMatch(text[end - 1])) {
      end++;
    }

    final slice = text.substring(start, end).trim().replaceAll(RegExp(r'\s+'), ' ');
    return '${start > 0 ? '…' : ''}$slice${end < text.length ? '…' : ''}';
  }

  /// Neutralises LIKE wildcards in a value that is matched as a literal.
  ///
  /// Without this, a substance recorded as "co_trimoxazole" would match
  /// "co-trimoxazole", "cotrimoxazole" and anything else with one character
  /// there. On a recall list, silently matching too much is as wrong as
  /// matching too little.
  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}

class _Clause {
  const _Clause(this.sql, this.args, this.isFiltered);

  final String sql;
  final List<Object?> args;

  /// False when the clause is only the soft-delete and deceased guards, i.e.
  /// the query selects everyone.
  final bool isFiltered;
}
