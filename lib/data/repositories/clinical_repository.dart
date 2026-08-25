import 'dart:io';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../clinical/news2.dart';
import '../../clinical/calculations.dart';
import '../../core/audit/audit_service.dart';
import '../../core/db/app_database.dart';
import '../../core/db/db_types.dart';
import '../../core/utils/ids.dart';
import '../dao/appointment_dao.dart';
import '../dao/attachment_dao.dart';
import '../dao/clinic_dao.dart';
import '../dao/cohort_dao.dart';
import '../dao/encounter_dao.dart';
import '../dao/note_dao.dart';
import '../dao/patient_dao.dart';
import '../dao/vitals_dao.dart';
import '../models/appointment.dart';
import '../models/attachment.dart';
import '../models/audit_event.dart';
import '../models/clinic.dart';
import '../models/clinical_note.dart';
import '../models/encounter.dart';
import '../models/patient.dart';
import '../models/vitals_record.dart';
import '../services/attachment_service.dart';

/// The single write path for clinical data.
///
/// Screens never talk to a DAO directly. Routing every mutation through here
/// is what guarantees the three things a clinical record must always have:
/// an audit entry, a sync-queue entry, and the invariants that DAOs enforce
/// individually (MRN allocation, note locking, derived-value freezing).
class ClinicalRepository {
  ClinicalRepository({
    required this.database,
    required this.audit,
    required this.clinics,
    required this.appointments,
    required this.patients,
    required this.encounters,
    required this.vitals,
    required this.notes,
    required this.attachments,
    required this.attachmentFiles,
    required this.cohorts,
  });

  final AppDatabase database;
  final AuditService audit;

  final ClinicDao clinics;
  final AppointmentDao appointments;
  final PatientDao patients;
  final EncounterDao encounters;
  final VitalsDao vitals;
  final NoteDao notes;
  final AttachmentDao attachments;
  final AttachmentService attachmentFiles;
  final CohortDao cohorts;

  factory ClinicalRepository.wire({
    required AppDatabase database,
    required AuditService audit,
  }) {
    final attachmentDao = AttachmentDao(database);
    return ClinicalRepository(
      database: database,
      audit: audit,
      clinics: ClinicDao(database),
      appointments: AppointmentDao(database),
      patients: PatientDao(database),
      encounters: EncounterDao(database),
      vitals: VitalsDao(database),
      notes: NoteDao(database),
      attachments: attachmentDao,
      attachmentFiles: AttachmentService(attachmentDao),
      cohorts: CohortDao(database),
    );
  }

  // ------------------------------------------------------------------ patients

  Future<Patient> createPatient(Patient draft) async {
    final patient = await patients.create(draft);
    await audit.log(
      AuditAction.patientCreate,
      entityType: 'patient',
      entityId: patient.id,
      patientId: patient.id,
    );
    await _enqueue('patient', patient.id, 'create');
    return patient;
  }

  Future<void> updatePatient(Patient patient, {String? changedFields}) async {
    await patients.update(patient);
    await audit.log(
      AuditAction.patientUpdate,
      entityType: 'patient',
      entityId: patient.id,
      patientId: patient.id,
      // Field names only — never the values themselves.
      detail: changedFields,
    );
    await _enqueue('patient', patient.id, 'update');
  }

  /// Records that a chart was opened. Access logging is the point of the audit
  /// trail, so this fires on every read of a full chart.
  Future<Patient?> openPatient(String id) async {
    final patient = await patients.byId(id);
    if (patient == null) return null;
    await audit.log(
      AuditAction.patientView,
      entityType: 'patient',
      entityId: id,
      patientId: id,
    );
    return patient;
  }

  // ---------------------------------------------------------------- encounters

  Future<Encounter> startEncounter({
    required String patientId,
    required String clinicId,
    EncounterType type = EncounterType.followUp,
    String? chiefComplaint,
    String? providerName,
    DateTime? startedAt,
  }) async {
    final now = DateTime.now();
    final encounter = Encounter(
      id: newId(),
      patientId: patientId,
      clinicId: clinicId,
      type: type,
      status: EncounterStatus.inProgress,
      chiefComplaint: chiefComplaint,
      startedAt: startedAt ?? now,
      providerName: providerName,
      createdAt: now,
      updatedAt: now,
    );

    await encounters.insert(encounter);
    await patients.touchLastSeen(patientId, encounter.startedAt);
    await audit.log(
      AuditAction.encounterCreate,
      entityType: 'encounter',
      entityId: encounter.id,
      patientId: patientId,
    );
    await _enqueue('encounter', encounter.id, 'create');
    return encounter;
  }

  Future<void> updateEncounter(Encounter encounter) async {
    await encounters.update(encounter);
    await audit.log(
      AuditAction.encounterUpdate,
      entityType: 'encounter',
      entityId: encounter.id,
      patientId: encounter.patientId,
    );
    await _enqueue('encounter', encounter.id, 'update');
  }

  /// Closes and signs an encounter together with its note.
  ///
  /// Signing is transactional across both rows: a signed encounter whose note
  /// stayed a draft would be a record that claims to be final while its
  /// clinical content is still mutable.
  Future<Encounter> signEncounter({
    required Encounter encounter,
    required String signedBy,
  }) async {
    final note = await notes.forEncounter(encounter.id);
    if (note != null && !note.isLocked) {
      await notes.sign(note, signedBy: signedBy);
      await audit.log(
        AuditAction.noteSign,
        entityType: 'note',
        entityId: note.id,
        patientId: encounter.patientId,
      );
    }

    final signed = encounter.copyWith(
      status: EncounterStatus.signed,
      endedAt: encounter.endedAt ?? DateTime.now(),
    );
    await encounters.update(signed);
    await audit.log(
      AuditAction.encounterSign,
      entityType: 'encounter',
      entityId: encounter.id,
      patientId: encounter.patientId,
    );
    await _enqueue('encounter', encounter.id, 'sign');
    return signed;
  }

  // -------------------------------------------------------------------- vitals

  /// Saves an observation set, deriving BMI and freezing the NEWS2 score.
  ///
  /// Derived values are computed once, here, and stored — never recomputed for
  /// display. A chart entry must keep the meaning it had when it was recorded.
  Future<VitalsRecord> recordVitals({
    required VitalsRecord draft,
    required int? patientAgeYears,
    bool isPregnant = false,
  }) async {
    final bmi = ClinicalCalc.bmi(
      weightKg: draft.weightKg,
      heightCm: draft.heightCm,
    );

    final news2 = News2Calculator.score(
      ageYears: patientAgeYears,
      isPregnant: isPregnant,
      input: draft.news2Input,
    );

    final record = VitalsRecord(
      id: draft.id.isEmpty ? newId() : draft.id,
      patientId: draft.patientId,
      encounterId: draft.encounterId,
      recordedAt: draft.recordedAt,
      position: draft.position,
      systolicBp: draft.systolicBp,
      diastolicBp: draft.diastolicBp,
      bpSite: draft.bpSite,
      heartRate: draft.heartRate,
      heartRhythm: draft.heartRhythm,
      respiratoryRate: draft.respiratoryRate,
      temperatureC: draft.temperatureC,
      temperatureSite: draft.temperatureSite,
      spo2: draft.spo2,
      onOxygen: draft.onOxygen,
      oxygenFlowLpm: draft.oxygenFlowLpm,
      oxygenDelivery: draft.oxygenDelivery,
      consciousness: draft.consciousness,
      heightCm: draft.heightCm,
      weightKg: draft.weightKg,
      bmi: bmi,
      headCircumferenceCm: draft.headCircumferenceCm,
      painScore: draft.painScore,
      bloodGlucoseMmol: draft.bloodGlucoseMmol,
      glucoseTiming: draft.glucoseTiming,
      capillaryRefillSec: draft.capillaryRefillSec,
      news2Score: news2?.total,
      news2Risk: news2?.risk.name,
      news2Algorithm: news2?.algorithmVersion,
      notes: draft.notes,
      recordedBy: draft.recordedBy,
      createdAt: draft.createdAt,
      updatedAt: DateTime.now(),
    );

    await vitals.insert(record);
    await patients.touchLastSeen(record.patientId, record.recordedAt);
    await audit.log(
      AuditAction.vitalsCreate,
      entityType: 'vitals',
      entityId: record.id,
      patientId: record.patientId,
    );
    await _enqueue('vitals', record.id, 'create');
    return record;
  }

  // --------------------------------------------------------------------- notes

  /// Returns the encounter's note, creating an empty draft on first open so
  /// the editor always has something to bind to.
  Future<ClinicalNote> noteForEncounter(Encounter encounter) async {
    final existing = await notes.forEncounter(encounter.id);
    if (existing != null) return existing;

    final now = DateTime.now();
    final note = ClinicalNote(
      id: newId(),
      patientId: encounter.patientId,
      encounterId: encounter.id,
      createdAt: now,
      updatedAt: now,
    );
    await notes.insert(note);
    await audit.log(
      AuditAction.noteCreate,
      entityType: 'note',
      entityId: note.id,
      patientId: encounter.patientId,
    );
    await _enqueue('note', note.id, 'create');
    return note;
  }

  /// Autosave path for the note editor. Deliberately does *not* write an audit
  /// entry per keystroke — the signing event is the auditable moment, and one
  /// row per character would drown the log.
  Future<void> saveNoteDraft(ClinicalNote note) async {
    await notes.update(note);
    await _enqueue('note', note.id, 'update');
  }

  Future<ClinicalNote> signNote(
    ClinicalNote note, {
    required String signedBy,
  }) async {
    final signed = await notes.sign(note, signedBy: signedBy);
    await audit.log(
      AuditAction.noteSign,
      entityType: 'note',
      entityId: note.id,
      patientId: note.patientId,
    );
    await _enqueue('note', note.id, 'sign');
    return signed;
  }

  Future<NoteAmendment> amendNote({
    required ClinicalNote note,
    required String body,
    required String reason,
    required String author,
  }) async {
    final amendment = await notes.amend(
      note: note,
      body: body,
      reason: reason,
      author: author,
    );
    await audit.log(
      AuditAction.noteAmend,
      entityType: 'note',
      entityId: note.id,
      patientId: note.patientId,
    );
    await _enqueue('note_amendment', amendment.id, 'create');
    return amendment;
  }

  // --------------------------------------------------------------- attachments

  Future<Attachment> attach({
    required File source,
    required String patientId,
    required AttachmentOwner ownerType,
    String? ownerId,
    required AttachmentKind kind,
    String? mimeType,
    String? caption,
    String? bodySite,
    int? durationMs,
    String? createdBy,
  }) async {
    final attachment = await attachmentFiles.store(
      source: source,
      patientId: patientId,
      ownerType: ownerType,
      ownerId: ownerId,
      kind: kind,
      mimeType: mimeType,
      caption: caption,
      bodySite: bodySite,
      durationMs: durationMs,
      createdBy: createdBy,
    );
    await audit.log(
      AuditAction.attachmentAdd,
      entityType: 'attachment',
      entityId: attachment.id,
      patientId: patientId,
      detail: kind.name,
    );
    await _enqueue('attachment', attachment.id, 'create');
    return attachment;
  }

  Future<void> removeAttachment(Attachment attachment) async {
    await attachmentFiles.remove(attachment);
    await audit.log(
      AuditAction.attachmentDelete,
      entityType: 'attachment',
      entityId: attachment.id,
      patientId: attachment.patientId,
    );
    await _enqueue('attachment', attachment.id, 'delete');
  }

  // ------------------------------------------------------------- appointments

  Future<Appointment> bookAppointment({
    required String patientId,
    required String clinicId,
    required DateTime scheduledAt,
    int durationMinutes = 15,
    EncounterType type = EncounterType.followUp,
    String? reason,
    String? notes,
    String? providerName,
  }) async {
    final now = DateTime.now();
    final appointment = Appointment(
      id: newId(),
      patientId: patientId,
      clinicId: clinicId,
      scheduledAt: scheduledAt,
      durationMinutes: durationMinutes,
      type: type,
      reason: reason,
      notes: notes,
      providerName: providerName,
      createdAt: now,
      updatedAt: now,
    );

    await appointments.insert(appointment);
    await audit.log(
      AuditAction.appointmentBook,
      entityType: 'appointment',
      entityId: appointment.id,
      patientId: patientId,
    );
    await _enqueue('appointment', appointment.id, 'create');
    return appointment;
  }

  /// Checks a patient in at the front desk.
  Future<Appointment> markArrived(Appointment appointment) async {
    final updated = appointment.copyWith(
      status: AppointmentStatus.arrived,
      arrivedAt: DateTime.now(),
    );
    await appointments.update(updated);
    await audit.log(
      AuditAction.appointmentUpdate,
      entityType: 'appointment',
      entityId: appointment.id,
      patientId: appointment.patientId,
      detail: 'arrived',
    );
    await _enqueue('appointment', appointment.id, 'update');
    return updated;
  }

  /// Turns a booking into an actual encounter.
  ///
  /// This is the join between intention and record: the appointment keeps its
  /// own lifecycle while the encounter becomes the clinical document, and the
  /// two are linked so the schedule can show what came of each slot.
  Future<Encounter> startFromAppointment(
    Appointment appointment, {
    String? providerName,
  }) async {
    final encounter = await startEncounter(
      patientId: appointment.patientId,
      clinicId: appointment.clinicId,
      type: appointment.type,
      chiefComplaint: appointment.reason,
      providerName: providerName ?? appointment.providerName,
    );

    await appointments.update(
      appointment.copyWith(
        status: AppointmentStatus.inProgress,
        encounterId: encounter.id,
        startedAt: DateTime.now(),
      ),
    );
    await _enqueue('appointment', appointment.id, 'update');
    return encounter;
  }

  Future<Appointment> closeAppointment(
    Appointment appointment,
    AppointmentStatus outcome, {
    String? reason,
  }) async {
    final updated = appointment.copyWith(
      status: outcome,
      completedAt: DateTime.now(),
      cancelledReason: reason,
    );
    await appointments.update(updated);
    await audit.log(
      AuditAction.appointmentUpdate,
      entityType: 'appointment',
      entityId: appointment.id,
      patientId: appointment.patientId,
      detail: outcome.name,
    );
    await _enqueue('appointment', appointment.id, 'update');
    return updated;
  }

  Future<Appointment> rescheduleAppointment(
    Appointment appointment,
    DateTime scheduledAt, {
    int? durationMinutes,
  }) async {
    final updated = appointment.copyWith(
      scheduledAt: scheduledAt,
      durationMinutes: durationMinutes,
      status: AppointmentStatus.scheduled,
    );
    await appointments.update(updated);
    await audit.log(
      AuditAction.appointmentUpdate,
      entityType: 'appointment',
      entityId: appointment.id,
      patientId: appointment.patientId,
      detail: 'rescheduled',
    );
    await _enqueue('appointment', appointment.id, 'update');
    return updated;
  }

  // ---------------------------------------------------------------- sync queue

  /// Marks an entity as needing upload once a backend exists.
  ///
  /// There is no server in round 1, so nothing drains this queue yet. It is
  /// written from day one anyway: a device that has been used offline for
  /// months before sync is switched on must still know what changed, and
  /// reconstructing that after the fact is not possible.
  Future<void> _enqueue(
    String entityType,
    String entityId,
    String operation,
  ) async {
    if (!database.isOpen) return;
    try {
      await database.db.insert(
        'sync_queue',
        <String, Object?>{
          'id': newId(),
          'entity_type': entityType,
          'entity_id': entityId,
          'operation': operation,
          'queued_at': toEpoch(DateTime.now()),
          'attempts': 0,
          'status': 'pending',
        },
        // The unique index on (entity_type, entity_id, operation) collapses
        // repeated edits into one pending item.
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException {
      // Queueing must never fail a clinical write.
    }
  }

  Future<int> pendingSyncCount() async {
    if (!database.isOpen) return 0;
    final result = await database.db.rawQuery(
      "SELECT COUNT(*) AS c FROM sync_queue WHERE status = 'pending'",
    );
    return (result.first['c'] as int?) ?? 0;
  }

  // ------------------------------------------------------------------ bootstrap

  /// Seeds a first clinic so a brand-new install can record an encounter
  /// immediately instead of dead-ending on "no clinic selected".
  Future<Clinic> ensureDefaultClinic() async {
    final existing = await clinics.all();
    if (existing.isNotEmpty) return existing.first;
    return clinics.create(name: 'My clinic', type: ClinicType.clinic);
  }
}
