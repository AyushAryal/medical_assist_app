/// Ordered DDL migrations for the encrypted clinical database.
///
/// Conventions applied throughout:
///
/// * Primary keys are UUID v4 `TEXT`, generated on device. Autoincrement
///   integers collide the moment two devices sync into one backend.
/// * Instants (`*_at`) are `INTEGER` epoch milliseconds in UTC.
/// * Calendar dates (`*_date`, `date_of_birth`) are `TEXT` `YYYY-MM-DD`. A
///   birthday must not shift when the device crosses a timezone.
/// * Nothing clinical is ever hard-deleted: rows carry `deleted_at` and are
///   filtered out by queries. Deleting a chart entry destroys evidence.
/// * Every syncable table carries `updated_at`, `revision` and `sync_status`
///   so the offline queue can do last-writer-wins with conflict detection.
abstract final class Schema {
  static const int version = 4;

  /// One list per schema version. Index 0 creates v1, index 1 upgrades v1→v2,
  /// and so on, so `onCreate` and `onUpgrade` replay exactly the same SQL.
  static const List<List<String>> migrations = <List<String>>[
    _v1,
    _v2,
    _v3,
    _v4,
  ];

  static const List<String> _v1 = <String>[
    '''
    CREATE TABLE app_meta (
      key         TEXT PRIMARY KEY,
      value       TEXT,
      updated_at  INTEGER NOT NULL
    )
    ''',

    '''
    CREATE TABLE clinics (
      id            TEXT PRIMARY KEY,
      name          TEXT NOT NULL,
      code          TEXT,
      type          TEXT NOT NULL DEFAULT 'clinic',
      address_line  TEXT,
      city          TEXT,
      district      TEXT,
      country       TEXT,
      phone         TEXT,
      timezone      TEXT,
      is_active     INTEGER NOT NULL DEFAULT 1,
      created_at    INTEGER NOT NULL,
      updated_at    INTEGER NOT NULL,
      deleted_at    INTEGER,
      revision      INTEGER NOT NULL DEFAULT 1,
      sync_status   TEXT NOT NULL DEFAULT 'pending'
    )
    ''',

    '''
    CREATE TABLE patients (
      id                TEXT PRIMARY KEY,
      mrn               TEXT NOT NULL,
      family_name       TEXT NOT NULL,
      given_name        TEXT NOT NULL,
      middle_name       TEXT,
      preferred_name    TEXT,
      sex_at_birth      TEXT NOT NULL DEFAULT 'unknown',
      gender_identity   TEXT,
      date_of_birth     TEXT,
      dob_is_estimated  INTEGER NOT NULL DEFAULT 0,
      blood_group       TEXT,
      phone             TEXT,
      alt_phone         TEXT,
      email             TEXT,
      address_line      TEXT,
      city              TEXT,
      district          TEXT,
      country           TEXT,
      national_id       TEXT,
      occupation        TEXT,
      next_of_kin_name  TEXT,
      next_of_kin_phone TEXT,
      next_of_kin_rel   TEXT,
      primary_clinic_id TEXT REFERENCES clinics(id),
      allergy_status    TEXT NOT NULL DEFAULT 'unknown',
      photo_path        TEXT,
      notes             TEXT,
      deceased_date     TEXT,
      search_index      TEXT NOT NULL DEFAULT '',
      last_seen_at      INTEGER,
      created_at        INTEGER NOT NULL,
      updated_at        INTEGER NOT NULL,
      deleted_at        INTEGER,
      revision          INTEGER NOT NULL DEFAULT 1,
      sync_status       TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE UNIQUE INDEX idx_patients_mrn ON patients(mrn)',
    'CREATE INDEX idx_patients_search ON patients(search_index)',
    'CREATE INDEX idx_patients_family ON patients(family_name, given_name)',
    'CREATE INDEX idx_patients_last_seen ON patients(last_seen_at DESC)',
    'CREATE INDEX idx_patients_clinic ON patients(primary_clinic_id)',

    '''
    CREATE TABLE allergies (
      id           TEXT PRIMARY KEY,
      patient_id   TEXT NOT NULL REFERENCES patients(id),
      substance    TEXT NOT NULL,
      category     TEXT NOT NULL DEFAULT 'drug',
      reaction     TEXT,
      severity     TEXT NOT NULL DEFAULT 'unknown',
      status       TEXT NOT NULL DEFAULT 'active',
      onset_date   TEXT,
      notes        TEXT,
      recorded_by  TEXT,
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL,
      deleted_at   INTEGER,
      revision     INTEGER NOT NULL DEFAULT 1,
      sync_status  TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX idx_allergies_patient ON allergies(patient_id, status)',

    '''
    CREATE TABLE problems (
      id            TEXT PRIMARY KEY,
      patient_id    TEXT NOT NULL REFERENCES patients(id),
      display       TEXT NOT NULL,
      code_system   TEXT,
      code          TEXT,
      status        TEXT NOT NULL DEFAULT 'active',
      is_chronic    INTEGER NOT NULL DEFAULT 0,
      onset_date    TEXT,
      resolved_date TEXT,
      notes         TEXT,
      recorded_by   TEXT,
      created_at    INTEGER NOT NULL,
      updated_at    INTEGER NOT NULL,
      deleted_at    INTEGER,
      revision      INTEGER NOT NULL DEFAULT 1,
      sync_status   TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX idx_problems_patient ON problems(patient_id, status)',

    '''
    CREATE TABLE medications (
      id           TEXT PRIMARY KEY,
      patient_id   TEXT NOT NULL REFERENCES patients(id),
      encounter_id TEXT REFERENCES encounters(id),
      name         TEXT NOT NULL,
      dose         TEXT,
      dose_unit    TEXT,
      route        TEXT,
      frequency    TEXT,
      duration     TEXT,
      indication   TEXT,
      status       TEXT NOT NULL DEFAULT 'active',
      started_on   TEXT,
      stopped_on   TEXT,
      stop_reason  TEXT,
      prescriber   TEXT,
      notes        TEXT,
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL,
      deleted_at   INTEGER,
      revision     INTEGER NOT NULL DEFAULT 1,
      sync_status  TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX idx_medications_patient ON medications(patient_id, status)',

    '''
    CREATE TABLE encounters (
      id               TEXT PRIMARY KEY,
      patient_id       TEXT NOT NULL REFERENCES patients(id),
      clinic_id        TEXT NOT NULL REFERENCES clinics(id),
      type             TEXT NOT NULL DEFAULT 'follow_up',
      status           TEXT NOT NULL DEFAULT 'draft',
      chief_complaint  TEXT,
      started_at       INTEGER NOT NULL,
      ended_at         INTEGER,
      disposition      TEXT,
      follow_up_date   TEXT,
      referred_to      TEXT,
      provider_name    TEXT,
      provider_id      TEXT,
      created_at       INTEGER NOT NULL,
      updated_at       INTEGER NOT NULL,
      deleted_at       INTEGER,
      revision         INTEGER NOT NULL DEFAULT 1,
      sync_status      TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX idx_encounters_patient ON encounters(patient_id, started_at DESC)',
    'CREATE INDEX idx_encounters_clinic_day ON encounters(clinic_id, started_at DESC)',
    'CREATE INDEX idx_encounters_status ON encounters(status, started_at DESC)',

    '''
    CREATE TABLE vitals (
      id                   TEXT PRIMARY KEY,
      patient_id           TEXT NOT NULL REFERENCES patients(id),
      encounter_id         TEXT REFERENCES encounters(id),
      recorded_at          INTEGER NOT NULL,
      position             TEXT,
      systolic_bp          INTEGER,
      diastolic_bp         INTEGER,
      bp_site              TEXT,
      heart_rate           INTEGER,
      heart_rhythm         TEXT,
      respiratory_rate     INTEGER,
      temperature_c        REAL,
      temperature_site     TEXT,
      spo2                 INTEGER,
      on_oxygen            INTEGER NOT NULL DEFAULT 0,
      oxygen_flow_lpm      REAL,
      oxygen_delivery      TEXT,
      consciousness        TEXT,
      height_cm            REAL,
      weight_kg            REAL,
      bmi                  REAL,
      head_circumference_cm REAL,
      pain_score           INTEGER,
      blood_glucose_mmol   REAL,
      glucose_timing       TEXT,
      capillary_refill_sec REAL,
      news2_score          INTEGER,
      news2_risk           TEXT,
      news2_algorithm      TEXT,
      notes                TEXT,
      recorded_by          TEXT,
      created_at           INTEGER NOT NULL,
      updated_at           INTEGER NOT NULL,
      deleted_at           INTEGER,
      revision             INTEGER NOT NULL DEFAULT 1,
      sync_status          TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX idx_vitals_patient ON vitals(patient_id, recorded_at DESC)',
    'CREATE INDEX idx_vitals_encounter ON vitals(encounter_id)',

    '''
    CREATE TABLE clinical_notes (
      id             TEXT PRIMARY KEY,
      patient_id     TEXT NOT NULL REFERENCES patients(id),
      encounter_id   TEXT NOT NULL REFERENCES encounters(id),
      note_type      TEXT NOT NULL DEFAULT 'soap',
      template_id    TEXT,
      subjective     TEXT,
      objective      TEXT,
      assessment     TEXT,
      plan           TEXT,
      status         TEXT NOT NULL DEFAULT 'draft',
      signed_at      INTEGER,
      signed_by      TEXT,
      content_hash   TEXT,
      created_at     INTEGER NOT NULL,
      updated_at     INTEGER NOT NULL,
      deleted_at     INTEGER,
      revision       INTEGER NOT NULL DEFAULT 1,
      sync_status    TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX idx_notes_encounter ON clinical_notes(encounter_id)',
    'CREATE INDEX idx_notes_patient ON clinical_notes(patient_id, created_at DESC)',
    'CREATE INDEX idx_notes_status ON clinical_notes(status, updated_at DESC)',

    '''
    CREATE TABLE note_amendments (
      id            TEXT PRIMARY KEY,
      note_id       TEXT NOT NULL REFERENCES clinical_notes(id),
      body          TEXT NOT NULL,
      reason        TEXT NOT NULL,
      author        TEXT,
      previous_hash TEXT,
      content_hash  TEXT,
      created_at    INTEGER NOT NULL,
      sync_status   TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX idx_amendments_note ON note_amendments(note_id, created_at)',

    '''
    CREATE TABLE attachments (
      id           TEXT PRIMARY KEY,
      patient_id   TEXT NOT NULL REFERENCES patients(id),
      owner_type   TEXT NOT NULL,
      owner_id     TEXT,
      kind         TEXT NOT NULL,
      file_name    TEXT NOT NULL,
      relative_path TEXT NOT NULL,
      mime_type    TEXT,
      size_bytes   INTEGER,
      sha256       TEXT,
      duration_ms  INTEGER,
      body_site    TEXT,
      caption      TEXT,
      captured_at  INTEGER,
      created_by   TEXT,
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL,
      deleted_at   INTEGER,
      revision     INTEGER NOT NULL DEFAULT 1,
      sync_status  TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX idx_attachments_owner ON attachments(owner_type, owner_id)',
    'CREATE INDEX idx_attachments_patient ON attachments(patient_id, created_at DESC)',

    '''
    CREATE TABLE audit_events (
      id           TEXT PRIMARY KEY,
      occurred_at  INTEGER NOT NULL,
      actor        TEXT,
      action       TEXT NOT NULL,
      entity_type  TEXT,
      entity_id    TEXT,
      patient_id   TEXT,
      detail       TEXT,
      device_id    TEXT,
      synced       INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_audit_time ON audit_events(occurred_at DESC)',
    'CREATE INDEX idx_audit_patient ON audit_events(patient_id, occurred_at DESC)',

    '''
    CREATE TABLE sync_queue (
      id           TEXT PRIMARY KEY,
      entity_type  TEXT NOT NULL,
      entity_id    TEXT NOT NULL,
      operation    TEXT NOT NULL,
      queued_at    INTEGER NOT NULL,
      attempts     INTEGER NOT NULL DEFAULT 0,
      last_attempt_at INTEGER,
      last_error   TEXT,
      status       TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX idx_sync_status ON sync_queue(status, queued_at)',
    'CREATE UNIQUE INDEX idx_sync_entity ON sync_queue(entity_type, entity_id, operation)',
  ];

  /// v2 — scheduling.
  ///
  /// An appointment is an *intention* to provide care; an encounter is the
  /// record that care happened. They are separate rows joined by
  /// `encounter_id`, because appointments get cancelled, missed and rebooked
  /// without any clinical record ever existing — and a no-show is itself
  /// information worth keeping.
  static const List<String> _v2 = <String>[
    '''
    CREATE TABLE appointments (
      id               TEXT PRIMARY KEY,
      patient_id       TEXT NOT NULL REFERENCES patients(id),
      clinic_id        TEXT NOT NULL REFERENCES clinics(id),
      encounter_id     TEXT REFERENCES encounters(id),
      scheduled_at     INTEGER NOT NULL,
      duration_minutes INTEGER NOT NULL DEFAULT 15,
      type             TEXT NOT NULL DEFAULT 'followUp',
      status           TEXT NOT NULL DEFAULT 'scheduled',
      reason           TEXT,
      notes            TEXT,
      provider_name    TEXT,
      arrived_at       INTEGER,
      started_at       INTEGER,
      completed_at     INTEGER,
      cancelled_reason TEXT,
      created_at       INTEGER NOT NULL,
      updated_at       INTEGER NOT NULL,
      deleted_at       INTEGER,
      revision         INTEGER NOT NULL DEFAULT 1,
      sync_status      TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX idx_appt_day ON appointments(scheduled_at)',
    'CREATE INDEX idx_appt_clinic_day ON appointments(clinic_id, scheduled_at)',
    'CREATE INDEX idx_appt_patient ON appointments(patient_id, scheduled_at DESC)',
    'CREATE INDEX idx_appt_status ON appointments(status, scheduled_at)',
  ];

  /// v3 — working notes.
  ///
  /// A scratch field on the note for the raw dictation a consultation
  /// produces, before any of it has been sorted into S/O/A/P. It is
  /// deliberately **not** part of `canonicalContent()` and therefore not
  /// covered by the signature: it is working material, not record. The editor
  /// clears it at signing and warns first if anything is still sitting in it,
  /// so unsorted dictation cannot silently fail to reach the record.
  static const List<String> _v3 = <String>[
    'ALTER TABLE clinical_notes ADD COLUMN working_notes TEXT',
  ];

  /// v4 — smart phrases.
  ///
  /// User-editable text expansions summoned with `\` in any smart field (the
  /// dynamic macros like `\pat` live in code, not here — they resolve at
  /// runtime). `trigger` is the word typed after the backslash; `body` is what
  /// it expands to. Seeded with a handful of popular clinical phrases marked
  /// `is_builtin`, which the editor may still change or remove — a seed, not a
  /// lock. Syncable like everything else so a clinic's vocabulary travels.
  static const List<String> _v4 = <String>[
    '''
    CREATE TABLE smart_phrases (
      id           TEXT PRIMARY KEY,
      trigger      TEXT NOT NULL,
      title        TEXT NOT NULL,
      body         TEXT NOT NULL,
      is_builtin   INTEGER NOT NULL DEFAULT 0,
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL,
      deleted_at   INTEGER,
      revision     INTEGER NOT NULL DEFAULT 1,
      sync_status  TEXT NOT NULL DEFAULT 'pending'
    )
    ''',
    'CREATE INDEX idx_smart_phrase_trigger ON smart_phrases(trigger)',

    // Popular defaults, seeded once. Fixed ids so a replay never duplicates;
    // timestamps from the DB clock so they sort sensibly. No apostrophes in any
    // body, so no SQL escaping is needed to keep these const. `\n` becomes a
    // real newline in the stored text.
    "INSERT INTO smart_phrases (id, trigger, title, body, is_builtin, created_at, updated_at, revision, sync_status) VALUES "
        "('seed-normal', 'normal', 'Normal examination', "
        "'Patient appears well and in no acute distress. Examined systems are within normal limits.', "
        "1, CAST(strftime('%s','now') AS INTEGER) * 1000, CAST(strftime('%s','now') AS INTEGER) * 1000, 1, 'synced')",
    "INSERT INTO smart_phrases (id, trigger, title, body, is_builtin, created_at, updated_at, revision, sync_status) VALUES "
        "('seed-ros', 'ros', 'Review of systems', "
        "'General: no fever, night sweats or weight change.\nCardiorespiratory: no chest pain, palpitations, cough or breathlessness.\nGI: no abdominal pain, nausea, vomiting or change in bowel habit.\nNeuro: no headache, dizziness, weakness or numbness.', "
        "1, CAST(strftime('%s','now') AS INTEGER) * 1000, CAST(strftime('%s','now') AS INTEGER) * 1000, 1, 'synced')",
    "INSERT INTO smart_phrases (id, trigger, title, body, is_builtin, created_at, updated_at, revision, sync_status) VALUES "
        "('seed-fu1w', 'fu1w', 'Follow up in 1 week', "
        "'Follow up in 1 week, or sooner if symptoms worsen.', "
        "1, CAST(strftime('%s','now') AS INTEGER) * 1000, CAST(strftime('%s','now') AS INTEGER) * 1000, 1, 'synced')",
    "INSERT INTO smart_phrases (id, trigger, title, body, is_builtin, created_at, updated_at, revision, sync_status) VALUES "
        "('seed-fu2w', 'fu2w', 'Follow up in 2 weeks', "
        "'Follow up in 2 weeks, or sooner if symptoms worsen.', "
        "1, CAST(strftime('%s','now') AS INTEGER) * 1000, CAST(strftime('%s','now') AS INTEGER) * 1000, 1, 'synced')",
    "INSERT INTO smart_phrases (id, trigger, title, body, is_builtin, created_at, updated_at, revision, sync_status) VALUES "
        "('seed-safety', 'safety', 'Safety-netting', "
        "'Advised to return immediately if symptoms worsen, breathing becomes difficult, fluids cannot be kept down, or any new concern arises.', "
        "1, CAST(strftime('%s','now') AS INTEGER) * 1000, CAST(strftime('%s','now') AS INTEGER) * 1000, 1, 'synced')",
    "INSERT INTO smart_phrases (id, trigger, title, body, is_builtin, created_at, updated_at, revision, sync_status) VALUES "
        "('seed-counsel', 'counsel', 'Counselling given', "
        "'Diagnosis, management plan and expected course explained in plain language. Questions answered. Patient understands and agrees with the plan.', "
        "1, CAST(strftime('%s','now') AS INTEGER) * 1000, CAST(strftime('%s','now') AS INTEGER) * 1000, 1, 'synced')",
  ];
}
