import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_types.dart';
import '../models/appointment.dart';

class AppointmentDao {
  AppointmentDao(this._database);

  final AppDatabase _database;
  static const String table = 'appointments';

  Database get _db => _database.db;

  Future<Appointment?> byId(String id) async {
    final rows = await _db.query(
      table,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Appointment.fromMap(rows.first);
  }

  /// Everything booked for one local calendar day, in slot order.
  Future<List<Appointment>> forDay(DateTime day, {String? clinicId}) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final where = StringBuffer(
      'deleted_at IS NULL AND scheduled_at >= ? AND scheduled_at < ?',
    );
    final args = <Object?>[toEpoch(start), toEpoch(end)];
    if (clinicId != null) {
      where.write(' AND clinic_id = ?');
      args.add(clinicId);
    }

    final rows = await _db.query(
      table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'scheduled_at ASC',
    );
    return rows.map(Appointment.fromMap).toList();
  }

  /// Every appointment between [from] (inclusive) and [to] (exclusive).
  ///
  /// The calendar needs a whole month in one query. Calling [forDay] thirty-one
  /// times would be thirty-one round trips to an encrypted database to paint
  /// one screen, and the month grid is a screen people flick through.
  Future<List<Appointment>> forRange(
    DateTime from,
    DateTime to, {
    String? clinicId,
  }) async {
    final where = StringBuffer(
      'deleted_at IS NULL AND scheduled_at >= ? AND scheduled_at < ?',
    );
    final args = <Object?>[
      toEpoch(DateTime(from.year, from.month, from.day)),
      toEpoch(DateTime(to.year, to.month, to.day)),
    ];
    if (clinicId != null) {
      where.write(' AND clinic_id = ?');
      args.add(clinicId);
    }

    final rows = await _db.query(
      table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'scheduled_at ASC',
    );
    return rows.map(Appointment.fromMap).toList();
  }

  /// Patients who have checked in and are still waiting to be seen.
  Future<List<Appointment>> waitingRoom({String? clinicId}) async {
    final where = StringBuffer('deleted_at IS NULL AND status = ?');
    final args = <Object?>[AppointmentStatus.arrived.name];
    if (clinicId != null) {
      where.write(' AND clinic_id = ?');
      args.add(clinicId);
    }
    final rows = await _db.query(
      table,
      where: where.toString(),
      whereArgs: args,
      // Longest wait first — the fairest order and the one people expect.
      orderBy: 'arrived_at ASC',
    );
    return rows.map(Appointment.fromMap).toList();
  }

  /// The next open slots from [from] onward.
  Future<List<Appointment>> upcoming({
    DateTime? from,
    String? clinicId,
    int limit = 20,
  }) async {
    final where = StringBuffer(
      'deleted_at IS NULL AND scheduled_at >= ? AND status IN (?, ?, ?, ?)',
    );
    final args = <Object?>[
      toEpoch(from ?? DateTime.now()),
      AppointmentStatus.scheduled.name,
      AppointmentStatus.confirmed.name,
      AppointmentStatus.arrived.name,
      AppointmentStatus.inProgress.name,
    ];
    if (clinicId != null) {
      where.write(' AND clinic_id = ?');
      args.add(clinicId);
    }

    final rows = await _db.query(
      table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'scheduled_at ASC',
      limit: limit,
    );
    return rows.map(Appointment.fromMap).toList();
  }

  Future<List<Appointment>> forPatient(String patientId, {int limit = 50}) async {
    final rows = await _db.query(
      table,
      where: 'patient_id = ? AND deleted_at IS NULL',
      whereArgs: [patientId],
      orderBy: 'scheduled_at DESC',
      limit: limit,
    );
    return rows.map(Appointment.fromMap).toList();
  }

  /// Slots that already overlap an existing booking, so double-booking is a
  /// deliberate act rather than an accident.
  Future<List<Appointment>> conflicts({
    required String clinicId,
    required DateTime start,
    required int durationMinutes,
    String? excludingId,
  }) async {
    final end = start.add(Duration(minutes: durationMinutes));
    final dayStart = DateTime(start.year, start.month, start.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final rows = await _db.query(
      table,
      where: 'deleted_at IS NULL AND clinic_id = ? '
          'AND scheduled_at >= ? AND scheduled_at < ? '
          'AND status NOT IN (?, ?)',
      whereArgs: [
        clinicId,
        toEpoch(dayStart),
        toEpoch(dayEnd),
        AppointmentStatus.cancelled.name,
        AppointmentStatus.noShow.name,
      ],
    );

    return rows
        .map(Appointment.fromMap)
        .where((a) => a.id != excludingId)
        // Half-open overlap: touching slots do not conflict.
        .where((a) => a.scheduledAt.isBefore(end) && a.scheduledEnd.isAfter(start))
        .toList();
  }

  Future<int> countForDay(DateTime day, {String? clinicId}) async {
    final appointments = await forDay(day, clinicId: clinicId);
    return appointments.where((a) => !a.status.isFinished).length;
  }

  Future<Appointment> insert(Appointment appointment) async {
    await _db.insert(table, appointment.toMap());
    return appointment;
  }

  Future<void> update(Appointment appointment) async {
    await _db.update(
      table,
      appointment.toMap(),
      where: 'id = ?',
      whereArgs: [appointment.id],
    );
  }

  /// Cancellations are recorded, never erased — a cancelled slot is part of
  /// the patient's contact history.
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
}
