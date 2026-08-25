import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_types.dart';
import '../../core/utils/ids.dart';
import '../models/clinical_note.dart';

class NoteDao {
  NoteDao(this._database);

  final AppDatabase _database;
  static const String table = 'clinical_notes';
  static const String amendmentTable = 'note_amendments';

  Database get _db => _database.db;

  Future<ClinicalNote?> byId(String id) async {
    final rows = await _db.query(
      table,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ClinicalNote.fromMap(rows.first);
  }

  Future<ClinicalNote?> forEncounter(String encounterId) async {
    final rows = await _db.query(
      table,
      where: 'encounter_id = ? AND deleted_at IS NULL',
      whereArgs: [encounterId],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : ClinicalNote.fromMap(rows.first);
  }

  Future<List<ClinicalNote>> forPatient(String patientId, {int limit = 50}) async {
    final rows = await _db.query(
      table,
      where: 'patient_id = ? AND deleted_at IS NULL',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ClinicalNote.fromMap).toList();
  }

  /// The previous signed note for this patient. Powers "copy forward", which
  /// is the single biggest time-saver on a follow-up consultation.
  Future<ClinicalNote?> previousSigned(
    String patientId, {
    String? excludingEncounterId,
  }) async {
    final where = StringBuffer(
      'patient_id = ? AND deleted_at IS NULL AND status IN (?, ?)',
    );
    final args = <Object?>[
      patientId,
      NoteStatus.signed.name,
      NoteStatus.amended.name,
    ];
    if (excludingEncounterId != null) {
      where.write(' AND encounter_id != ?');
      args.add(excludingEncounterId);
    }
    final rows = await _db.query(
      table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'signed_at DESC, created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : ClinicalNote.fromMap(rows.first);
  }

  /// Unsigned drafts across all patients, oldest first. This is the chart
  /// backlog — the thing clinicians are chased about and the reason the
  /// dashboard leads with it.
  Future<List<ClinicalNote>> drafts({int limit = 100}) async {
    final rows = await _db.query(
      table,
      where: 'deleted_at IS NULL AND status = ?',
      whereArgs: [NoteStatus.draft.name],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(ClinicalNote.fromMap).toList();
  }

  Future<int> draftCount() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table '
      'WHERE deleted_at IS NULL AND status = ?',
      [NoteStatus.draft.name],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<ClinicalNote> insert(ClinicalNote note) async {
    await _db.insert(table, note.toMap());
    return note;
  }

  /// Rejects writes to a signed note at the data layer, not just in the UI.
  /// A locked record must stay locked no matter which screen calls in.
  Future<void> update(ClinicalNote note) async {
    final current = await byId(note.id);
    if (current != null && current.isLocked) {
      throw StateError(
        'Note ${note.id} is ${current.status.name} and cannot be edited. '
        'Add an amendment instead.',
      );
    }
    await _db.update(table, note.toMap(), where: 'id = ?', whereArgs: [note.id]);
  }

  /// Signs the note: freezes the content, stamps the author and time, and
  /// stores the integrity hash.
  Future<ClinicalNote> sign(ClinicalNote note, {required String signedBy}) async {
    if (note.isLocked) {
      throw StateError('Note ${note.id} is already signed.');
    }
    if (note.isEmpty) {
      throw StateError('Refusing to sign an empty note.');
    }

    final signed = note.copyWith(
      status: NoteStatus.signed,
      signedAt: DateTime.now(),
      signedBy: signedBy,
    );
    final withHash = signed.copyWith(contentHash: signed.computeHash());

    await _db.update(
      table,
      withHash.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
    return withHash;
  }

  Future<List<NoteAmendment>> amendments(String noteId) async {
    final rows = await _db.query(
      amendmentTable,
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'created_at ASC',
    );
    return rows.map(NoteAmendment.fromMap).toList();
  }

  /// Appends a correction to a signed note and chains it to the previous
  /// entry's hash, so the amendment history is tamper-evident.
  Future<NoteAmendment> amend({
    required ClinicalNote note,
    required String body,
    required String reason,
    required String author,
  }) async {
    if (!note.isLocked) {
      throw StateError('Only signed notes are amended; edit the draft instead.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('An amendment must state its reason.');
    }

    final existing = await amendments(note.id);
    final previousHash =
        existing.isEmpty ? note.contentHash : existing.last.contentHash;

    final amendment = NoteAmendment(
      id: newId(),
      noteId: note.id,
      body: body,
      reason: reason,
      author: author,
      previousHash: previousHash,
      createdAt: DateTime.now(),
    );

    await _db.transaction((txn) async {
      await txn.insert(amendmentTable, amendment.toMap());
      await txn.update(
        table,
        {
          'status': NoteStatus.amended.name,
          'updated_at': toEpoch(DateTime.now()),
          'sync_status': SyncStatus.pending,
        },
        where: 'id = ?',
        whereArgs: [note.id],
      );
    });

    return amendment;
  }
}
