import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_types.dart';
import '../../core/utils/ids.dart';
import '../models/allergy.dart';
import '../models/medication.dart';
import '../models/patient.dart';
import '../models/problem.dart';

/// Everything on the patient chart header: demographics plus the three lists
/// (allergies, problems, medications) a clinician reads before consulting.
class PatientDao {
  PatientDao(this._database);

  final AppDatabase _database;
  static const String table = 'patients';

  Database get _db => _database.db;

  Future<Patient?> byId(String id) async {
    final rows = await _db.query(
      table,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Patient.fromMap(rows.first);
  }

  Future<Patient?> byMrn(String mrn) async {
    final rows = await _db.query(
      table,
      where: 'mrn = ? AND deleted_at IS NULL',
      whereArgs: [mrn],
      limit: 1,
    );
    return rows.isEmpty ? null : Patient.fromMap(rows.first);
  }

  /// Token-AND search over the denormalised `search_index`: every whitespace
  /// separated term must appear, so "john 07" narrows rather than widens.
  Future<List<Patient>> search(String query, {int limit = 50}) async {
    final terms = query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    if (terms.isEmpty) return recent(limit: limit);

    final clauses = List.filled(terms.length, 'search_index LIKE ?').join(' AND ');
    final rows = await _db.query(
      table,
      where: 'deleted_at IS NULL AND $clauses',
      whereArgs: terms.map((t) => '%$t%').toList(),
      orderBy: 'last_seen_at DESC, family_name COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map(Patient.fromMap).toList();
  }

  /// Most recently seen first — on a shared clinic device this is almost
  /// always the list the user actually wants.
  Future<List<Patient>> recent({int limit = 20}) async {
    final rows = await _db.query(
      table,
      where: 'deleted_at IS NULL',
      orderBy: 'last_seen_at DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(Patient.fromMap).toList();
  }

  Future<int> count() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE deleted_at IS NULL',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// Allocates the next MRN. Wrapped in a transaction with the insert by
  /// [create] so two rapid registrations cannot claim the same number.
  Future<String> _nextMrn(DatabaseExecutor txn) async {
    final result = await txn.rawQuery(
      'SELECT MAX(CAST(mrn AS INTEGER)) AS m FROM $table',
    );
    final maxMrn = (result.first['m'] as int?) ?? 0;
    return formatMrn(maxMrn + 1);
  }

  Future<Patient> create(Patient draft) async {
    return _db.transaction<Patient>((txn) async {
      final mrn = draft.mrn.isEmpty ? await _nextMrn(txn) : draft.mrn;
      final now = DateTime.now();
      final patient = Patient(
        id: draft.id.isEmpty ? newId() : draft.id,
        mrn: mrn,
        familyName: draft.familyName,
        givenName: draft.givenName,
        middleName: draft.middleName,
        preferredName: draft.preferredName,
        sexAtBirth: draft.sexAtBirth,
        genderIdentity: draft.genderIdentity,
        dateOfBirth: draft.dateOfBirth,
        dobIsEstimated: draft.dobIsEstimated,
        bloodGroup: draft.bloodGroup,
        phone: draft.phone,
        altPhone: draft.altPhone,
        email: draft.email,
        addressLine: draft.addressLine,
        city: draft.city,
        district: draft.district,
        country: draft.country,
        nationalId: draft.nationalId,
        occupation: draft.occupation,
        nextOfKinName: draft.nextOfKinName,
        nextOfKinPhone: draft.nextOfKinPhone,
        nextOfKinRelation: draft.nextOfKinRelation,
        primaryClinicId: draft.primaryClinicId,
        allergyStatus: draft.allergyStatus,
        photoPath: draft.photoPath,
        notes: draft.notes,
        createdAt: now,
        updatedAt: now,
      );
      await txn.insert(table, patient.toMap());
      return patient;
    });
  }

  Future<void> update(Patient patient) async {
    await _db.update(
      table,
      patient.toMap(),
      where: 'id = ?',
      whereArgs: [patient.id],
    );
  }

  Future<void> touchLastSeen(String patientId, DateTime seenAt) async {
    await _db.update(
      table,
      {'last_seen_at': toEpoch(seenAt)},
      where: 'id = ?',
      whereArgs: [patientId],
    );
  }

  /// Soft delete only. Removing a chart destroys the record of care that was
  /// given, which is exactly what an audit needs to see.
  Future<void> archive(String id) async {
    await _db.update(
      table,
      {
        'deleted_at': toEpoch(DateTime.now()),
        'sync_status': SyncStatus.pending,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------- allergies

  Future<List<Allergy>> allergies(String patientId, {bool activeOnly = true}) async {
    final rows = await _db.query(
      'allergies',
      where: activeOnly
          ? 'patient_id = ? AND deleted_at IS NULL AND status = ?'
          : 'patient_id = ? AND deleted_at IS NULL',
      whereArgs: activeOnly
          ? [patientId, AllergyRecordStatus.active.name]
          : [patientId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Allergy.fromMap).toList();
  }

  Future<Allergy> addAllergy(Allergy allergy) async {
    await _db.insert('allergies', allergy.toMap());
    // Keep the header banner in step with the list.
    await _db.update(
      table,
      {'allergy_status': AllergyStatus.hasAllergies.name},
      where: 'id = ?',
      whereArgs: [allergy.patientId],
    );
    return allergy;
  }

  Future<void> updateAllergy(Allergy allergy) async {
    await _db.update(
      'allergies',
      allergy.toMap(),
      where: 'id = ?',
      whereArgs: [allergy.id],
    );
  }

  // ----------------------------------------------------------------- problems

  Future<List<Problem>> problems(String patientId, {bool activeOnly = false}) async {
    final rows = await _db.query(
      'problems',
      where: activeOnly
          ? 'patient_id = ? AND deleted_at IS NULL AND status = ?'
          : 'patient_id = ? AND deleted_at IS NULL',
      whereArgs:
          activeOnly ? [patientId, ProblemStatus.active.name] : [patientId],
      orderBy: 'status ASC, is_chronic DESC, created_at DESC',
    );
    return rows.map(Problem.fromMap).toList();
  }

  Future<Problem> addProblem(Problem problem) async {
    await _db.insert('problems', problem.toMap());
    return problem;
  }

  Future<void> updateProblem(Problem problem) async {
    await _db.update(
      'problems',
      problem.toMap(),
      where: 'id = ?',
      whereArgs: [problem.id],
    );
  }

  // -------------------------------------------------------------- medications

  Future<List<Medication>> medications(
    String patientId, {
    bool activeOnly = false,
  }) async {
    final rows = await _db.query(
      'medications',
      where: activeOnly
          ? 'patient_id = ? AND deleted_at IS NULL AND status = ?'
          : 'patient_id = ? AND deleted_at IS NULL',
      whereArgs:
          activeOnly ? [patientId, MedicationStatus.active.name] : [patientId],
      orderBy: 'status ASC, created_at DESC',
    );
    return rows.map(Medication.fromMap).toList();
  }

  Future<Medication> addMedication(Medication medication) async {
    await _db.insert('medications', medication.toMap());
    return medication;
  }

  Future<void> updateMedication(Medication medication) async {
    await _db.update(
      'medications',
      medication.toMap(),
      where: 'id = ?',
      whereArgs: [medication.id],
    );
  }
}
