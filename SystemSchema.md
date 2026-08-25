# System Schema

Database schema for the on-device encrypted clinical store.
Authoritative DDL lives in [`lib/core/db/schema.dart`](lib/core/db/schema.dart);
this document explains the *why*.

- **Engine**: SQLite via SQLCipher (AES-256, page-level)
- **Schema version**: 2
- **File**: `<app documents>/clinical.enc.db`
- **Foreign keys**: enforced per connection (`PRAGMA foreign_keys = ON`)

---

## Conventions

| Convention | Applies to | Reason |
|---|---|---|
| `TEXT` UUID v4 primary keys | every table | Device-generated IDs must not collide when several offline devices later sync into one dataset. Autoincrement integers guarantee they will. |
| `INTEGER` epoch milliseconds, UTC | all `*_at` columns | Unambiguous ordering; immune to the device changing timezone or DST. |
| `TEXT` `YYYY-MM-DD` | all `*_date` columns, `date_of_birth`, `started_on` | A birthday stored as an instant shifts by a day when the device crosses a timezone. A calendar date is a calendar date. |
| `deleted_at INTEGER NULL` | all clinical tables | Soft delete only. Removing a chart entry destroys evidence of the care that was given — exactly what an audit needs to see. All queries filter `deleted_at IS NULL`. |
| `revision INTEGER` | all syncable tables | Monotonic per row; bumped by every `copyWith`. Basis for conflict detection. |
| `sync_status TEXT` | all syncable tables | `pending` / `synced` / `conflict`. Defaults to `pending`. |
| Enums stored as `TEXT` | throughout | Readable in a database browser during support; parsers fall back to a safe default rather than throwing on an unknown value. |
| Derived values stored | `vitals.bmi`, `vitals.news2_*`, `clinical_notes.content_hash` | A historic row must keep the meaning it had when it was recorded. Recomputing on read means revising an algorithm silently rewrites the past. |

Every syncable table carries this **record envelope**:

```sql
created_at   INTEGER NOT NULL,
updated_at   INTEGER NOT NULL,
deleted_at   INTEGER,
revision     INTEGER NOT NULL DEFAULT 1,
sync_status  TEXT    NOT NULL DEFAULT 'pending'
```

---

## Entity relationships

```
                    ┌──────────┐
                    │ clinics  │
                    └────┬─────┘
                         │ 1
              ┌──────────┴───────────┐
              │ N                    │ N
        ┌─────▼──────┐         ┌─────▼──────┐
        │  patients  │────1:N──│ encounters │
        └─────┬──────┘         └─────┬──────┘
              │ 1                    │ 1
   ┌──────────┼──────────┐           ├────────────────┐
   │ N        │ N        │ N         │ 1              │ N
┌──▼──────┐┌──▼───────┐┌─▼─────────┐ │         ┌──────▼──────┐
│allergies││ problems ││medications│ │         │   vitals    │
└─────────┘└──────────┘└───────────┘ │         └─────────────┘
                                     │
                              ┌──────▼─────────┐
                              │ clinical_notes │──1:N──┐
                              └────────────────┘       │
                                                ┌──────▼──────────┐
                                                │ note_amendments │
                                                └─────────────────┘

  attachments ──► polymorphic (owner_type, owner_id) → patient | encounter | note | vitals
  audit_events ──► append-only, no FK (must survive the row it describes)
  sync_queue   ──► append-only work list
  app_meta     ──► key/value, inside the encrypted DB
```

---

## Tables

### `clinics`

Sites of care. Every encounter is stamped with one — the same clinician's notes
at a hospital and at a rural health post carry different context, formularies and
follow-up expectations.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | |
| `name` | TEXT NOT NULL | |
| `code` | TEXT | Local facility code |
| `type` | TEXT | `clinic` `hospital` `healthPost` `pharmacy` `homeVisit` `telehealth` |
| `address_line`, `city`, `district`, `country`, `phone` | TEXT | |
| `timezone` | TEXT | Reserved for cross-timezone practices |
| `is_active` | INTEGER | Soft-archived rather than deleted, so historic encounters keep pointing at where care happened |

### `patients`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | |
| `mrn` | TEXT NOT NULL, **UNIQUE** | Six-digit zero-padded. Allocated inside the insert transaction (`MAX(CAST(mrn AS INTEGER)) + 1`) so two rapid registrations cannot claim the same number. |
| `family_name`, `given_name`, `middle_name` | TEXT | |
| `preferred_name` | TEXT | What the patient is actually called |
| `sex_at_birth` | TEXT | `male` `female` `intersex` `unknown`. **Clinical** field — drives reference ranges, dosing and screening pathways. |
| `gender_identity` | TEXT | Free text. **Social** field — drives how the patient is addressed. Kept separate on purpose. |
| `date_of_birth` | TEXT | `YYYY-MM-DD` |
| `dob_is_estimated` | INTEGER | Set when only an approximate age was known. Rendered as `~34y` so an estimate is never mistaken for a verified date. |
| `blood_group` | TEXT | |
| `phone`, `alt_phone`, `email` | TEXT | |
| `address_line`, `city`, `district`, `country` | TEXT | |
| `national_id`, `occupation` | TEXT | |
| `next_of_kin_name/_phone/_rel` | TEXT | Who to contact when the patient cannot consent |
| `primary_clinic_id` | TEXT FK → clinics | |
| `allergy_status` | TEXT | `unknown` / `noKnownAllergies` / `hasAllergies`. **Three states on purpose** — "nothing recorded yet" and "asked, and there are none" are clinically different, and collapsing them is how an allergy gets missed. |
| `photo_path` | TEXT | Relative to app documents |
| `deceased_date` | TEXT | |
| `search_index` | TEXT NOT NULL | Denormalised lowercase `mrn + names + phone + national_id`. Keeps lookup a single indexed scan. Rebuilt on every `toMap()`. |
| `last_seen_at` | INTEGER | Drives recency-ordered lists |

Indexes: `mrn` (unique), `search_index`, `(family_name, given_name)`,
`last_seen_at DESC`, `primary_clinic_id`.

### `allergies`

| Column | Type | Notes |
|---|---|---|
| `patient_id` | TEXT FK | |
| `substance` | TEXT NOT NULL | |
| `category` | TEXT | `drug` `food` `environmental` `biologic` `other` |
| `reaction` | TEXT | What actually happened |
| `severity` | TEXT | `unknown` `mild` `moderate` `severe` `anaphylaxis`. `severe` and `anaphylaxis` trigger the full-width red banner. |
| `status` | TEXT | `active` `inactive` `refuted`. **`refuted` matters**: allergies are frequently mis-reported, and this preserves the history while removing it from the active banner. |
| `onset_date` | TEXT | |

Index: `(patient_id, status)`.

### `problems`

The running problem list — the summary a clinician reads first.

| Column | Type | Notes |
|---|---|---|
| `display` | TEXT NOT NULL | Free text, always authoritative for the clinician |
| `code_system`, `code` | TEXT | e.g. `ICD-10` / `E11.9`. Optional; for reporting and future interop only. |
| `status` | TEXT | `active` `resolved` `inactive` |
| `is_chronic` | INTEGER | Sorted to the top of the list |
| `onset_date`, `resolved_date` | TEXT | |

Index: `(patient_id, status)`.

### `medications`

| Column | Type | Notes |
|---|---|---|
| `name` | TEXT NOT NULL | |
| `dose`, `dose_unit`, `route`, `frequency`, `duration` | TEXT | Rendered as a sig line: `Amoxicillin 500 mg PO TDS × 5 days` |
| `indication` | TEXT | |
| `status` | TEXT | `active` `onHold` `completed` `stopped` |
| `started_on`, `stopped_on`, `stop_reason` | TEXT | |
| `encounter_id` | TEXT FK | Which visit prescribed it |

Index: `(patient_id, status)`.

### `encounters`

| Column | Type | Notes |
|---|---|---|
| `patient_id`, `clinic_id` | TEXT FK NOT NULL | |
| `type` | TEXT | `newPatient` `followUp` `emergency` `procedure` `telehealth` `homeVisit` `antenatal` `immunisation` |
| `status` | TEXT | `draft` → `inProgress` → `completed` → `signed` → `amended`; plus `cancelled`. `signed` and `amended` are **terminal for editing**. |
| `chief_complaint` | TEXT | The patient's own words, kept verbatim and separate from the assessment |
| `started_at`, `ended_at` | INTEGER | |
| `disposition` | TEXT | `home` `referred` `admitted` `observation` `transferred` `leftWithoutBeingSeen` `deceased` |
| `follow_up_date` | TEXT | Drives the dashboard's follow-ups-due list |
| `referred_to`, `provider_name`, `provider_id` | TEXT | |

Indexes: `(patient_id, started_at DESC)`, `(clinic_id, started_at DESC)`,
`(status, started_at DESC)`.

### `vitals`

`encounter_id` is **nullable on purpose**: vitals are routinely taken at triage
before anyone opens an encounter, and forcing an encounter first is the fastest
way to make staff record vitals on paper instead.

| Column | Type | Notes |
|---|---|---|
| `recorded_at` | INTEGER NOT NULL | |
| `position` | TEXT | `sitting` `supine` `standing` — a standing BP is not comparable with a supine one |
| `systolic_bp`, `diastolic_bp`, `bp_site` | INTEGER/TEXT | |
| `heart_rate`, `heart_rhythm` | INTEGER/TEXT | |
| `respiratory_rate` | INTEGER | |
| `temperature_c`, `temperature_site` | REAL/TEXT | Always Celsius; Fahrenheit is converted at entry |
| `spo2`, `on_oxygen`, `oxygen_flow_lpm`, `oxygen_delivery` | | Oxygen status is required for NEWS2 |
| `consciousness` | TEXT | ACVPU: `alert` `confusion` `voice` `pain` `unresponsive` |
| `height_cm`, `weight_kg`, `bmi` | REAL | **`bmi` is stored**, not recomputed on read |
| `head_circumference_cm` | REAL | Paediatric |
| `pain_score` | INTEGER | 0–10 |
| `blood_glucose_mmol`, `glucose_timing` | REAL/TEXT | Always mmol/L; mg/dL converted at entry |
| `capillary_refill_sec` | REAL | |
| `news2_score`, `news2_risk`, `news2_algorithm` | | **Frozen at capture** with the algorithm identifier (`NEWS2-RCP-2017`), so revising the scoring code never rewrites past observations |
| `recorded_by` | TEXT | |

Indexes: `(patient_id, recorded_at DESC)`, `encounter_id`.

### `clinical_notes`

The four SOAP sections are stored **separately** because they are read
separately — on a follow-up the clinician jumps straight to the previous
Assessment and Plan.

| Column | Type | Notes |
|---|---|---|
| `patient_id`, `encounter_id` | TEXT FK NOT NULL | |
| `note_type` | TEXT | `soap` `progress` `procedure` `referral` `discharge` `telephone` |
| `template_id` | TEXT | Which template seeded it |
| `subjective` | TEXT | What the patient reports |
| `objective` | TEXT | What the clinician finds |
| `assessment` | TEXT | Interpretation and differential |
| `plan` | TEXT | Investigations, treatment, safety-netting, follow-up |
| `status` | TEXT | `draft` `signed` `amended`. Non-draft is **locked at the DAO**, not just in the UI. |
| `signed_at`, `signed_by` | INTEGER/TEXT | |
| `content_hash` | TEXT | SHA-256 over a canonical JSON serialisation with fixed field order. Divergence between stored text and this hash is detectable tampering, surfaced as a red integrity banner. |

Indexes: `encounter_id`, `(patient_id, created_at DESC)`,
`(status, updated_at DESC)` — the last one backs the dashboard's unsigned-notes
count.

### `note_amendments`

Append-only corrections to signed notes. **No `deleted_at`** — an amendment
cannot be withdrawn.

| Column | Type | Notes |
|---|---|---|
| `note_id` | TEXT FK NOT NULL | |
| `body` | TEXT NOT NULL | |
| `reason` | TEXT NOT NULL | **Required.** A correction without a stated reason is not auditable. |
| `author` | TEXT | |
| `previous_hash` | TEXT | Chains to the note's `content_hash`, then to the prior amendment. Removing one from the middle of the chain is detectable. |

Index: `(note_id, created_at)`.

### `attachments`

Metadata only; bytes live in app-private storage.

| Column | Type | Notes |
|---|---|---|
| `owner_type`, `owner_id` | TEXT | Polymorphic: `patient` `encounter` `note` `vitals`. A wound photo belongs to an encounter; an ID scan belongs to the patient. |
| `kind` | TEXT | `photo` `document` `audio` `video` |
| `relative_path` | TEXT NOT NULL | **Relative** to app documents — absolute paths break on iOS, where the container UUID changes between installs and OS upgrades |
| `sha256` | TEXT | Detects a corrupted or swapped file |
| `duration_ms` | INTEGER | Audio |
| `body_site` | TEXT | Without it, wound photos taken three weeks apart cannot be reliably compared |
| `captured_at` | INTEGER | |

Indexes: `(owner_type, owner_id)`, `(patient_id, created_at DESC)`.

### `appointments` *(v2)*

An appointment is an **intention** to provide care; an [`encounters`](#encounters)
row is the record that care **happened**. They are separate tables joined by
`encounter_id`, because appointments are cancelled, missed and rebooked without
any clinical record ever existing — and a missed appointment is itself
clinically meaningful. A diabetic patient who misses three reviews is a safety
signal that only exists if the misses were recorded.

| Column | Type | Notes |
|---|---|---|
| `patient_id`, `clinic_id` | TEXT FK NOT NULL | |
| `encounter_id` | TEXT FK | Set when the visit actually starts |
| `scheduled_at` | INTEGER NOT NULL | |
| `duration_minutes` | INTEGER | Default 15 |
| `type` | TEXT | Same vocabulary as `encounters.type` |
| `status` | TEXT | `scheduled` `confirmed` `arrived` `inProgress` `completed` `noShow` `cancelled` |
| `reason` | TEXT | Booking reason; becomes the encounter's chief complaint |
| `arrived_at` | INTEGER | Drives the waiting-room list and the wait-time display |
| `started_at`, `completed_at` | INTEGER | |
| `cancelled_reason` | TEXT | |

Indexes: `scheduled_at`, `(clinic_id, scheduled_at)`,
`(patient_id, scheduled_at DESC)`, `(status, scheduled_at)`.

Overlap detection is done in Dart rather than SQL (`AppointmentDao.conflicts`)
because it needs half-open interval comparison against each row's own
duration. Conflicts **warn**; they never block. Double-booking is sometimes the
right call and the software should not overrule the person at the desk.

### `audit_events`

Append-only PHI access log. **No FK** — it must survive the row it describes.

| Column | Type | Notes |
|---|---|---|
| `occurred_at` | INTEGER NOT NULL | |
| `action` | TEXT NOT NULL | Includes **reads** (`patientView`) — "who looked at this chart" is where an access investigation starts |
| `actor`, `device_id` | TEXT | |
| `entity_type`, `entity_id`, `patient_id` | TEXT | |
| `detail` | TEXT | **Field names and counts only, never values.** An audit log that quotes the record it protects just doubles the PHI at risk. |
| `synced` | INTEGER | Only synced rows are eligible for retention purge |

Indexes: `occurred_at DESC`, `(patient_id, occurred_at DESC)`.

### `sync_queue`

Written on every mutation even though no backend exists — a device used offline
for months before sync is switched on must still know what changed, and that
cannot be reconstructed after the fact.

| Column | Type | Notes |
|---|---|---|
| `entity_type`, `entity_id`, `operation` | TEXT NOT NULL | |
| `queued_at`, `attempts`, `last_attempt_at`, `last_error` | | |
| `status` | TEXT | `pending` / … |

`UNIQUE (entity_type, entity_id, operation)` collapses repeated edits into a
single pending item.

### `app_meta`

Key/value settings held **inside** the encrypted database rather than in
`SharedPreferences`: `active_clinic_id`, `provider_name`, `device_id`,
`theme_mode`, `onboarded`. The active clinic and the signing clinician's name
are operational context for a medical record and do not belong in a
world-readable plist.

---

## Migrations

```dart
static const List<List<String>> migrations = <List<String>>[
  _v1,   // index 0 creates v1
  _v2,   // index 1 upgrades v1 → v2 (appointments)
];
```

`onCreate` replays indices `0..version-1`; `onUpgrade` replays
`oldVersion..newVersion-1`. Both execute the same SQL, so a fresh install and an
upgraded install converge on byte-identical schemas.

**Rules for adding a version:** append a new list, never edit an existing one;
additive changes only (SQLite cannot drop a column); ship a data-backfill step in
the same batch when a new column needs a non-default value.

---

## Query patterns

| Need | Query |
|---|---|
| Patient search | `search_index LIKE ?` AND-ed per token, ordered by `last_seen_at DESC` |
| Unsigned-note count | `clinical_notes WHERE status = 'draft'` — hits `idx_notes_status` |
| Today's encounters | `started_at` between local-midnight bounds, optionally filtered by clinic |
| Deteriorating patients | `vitals WHERE news2_score >= 5` within today, ordered by score |
| Vitals trend | `(patient_id, recorded_at DESC)` limit N |
| Follow-ups due | `follow_up_date <= ?` — string comparison is correct because dates are ISO-8601 |
