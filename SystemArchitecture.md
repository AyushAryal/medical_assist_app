# System Architecture

A Flutter clinical records application for a single clinician (or a small
practice) working across one or more sites, frequently offline. Every patient
record is held in an encrypted SQLite database on the device. There is no
backend, and none is contacted.

- **Flutter** 3.44 · **Dart** 3.12 · targets Android (minSdk 24) and iOS 13+
- **State**: `provider` (`ChangeNotifier`) · **Routing**: `go_router`
- **Storage**: `sqflite_sqlcipher` (SQLCipher, AES-256)
- **Secrets**: `flutter_secure_storage` (Android Keystore / iOS Keychain)
- **Biometrics**: `local_auth`

---

## 1. Layering

```
┌──────────────────────────────────────────────────────────────────┐
│  features/*          screens, sheets, per-feature controllers    │
├──────────────────────────────────────────────────────────────────┤
│  ClinicalRepository  THE single write path                       │
│                      audit + sync queue + invariants             │
├──────────────────────────────────────────────────────────────────┤
│  data/dao/*          SQL, per aggregate                          │
│  data/services/*     attachment bytes, voice capture             │
├──────────────────────────────────────────────────────────────────┤
│  core/db             SQLCipher handle, schema, migrations         │
│  core/security       DEK manager, PIN hashing, app lock          │
│  core/modules        entitlements, module registry               │
│  core/theme          JSON token loader → ThemeData               │
├──────────────────────────────────────────────────────────────────┤
│  ai/*                the assistant pipeline: one path from a     │
│                      question to an answer (see §4b)             │
├──────────────────────────────────────────────────────────────────┤
│  clinical/*          pure functions: NEWS2, ranges, calculations │
│                      no Flutter imports, fully unit-tested       │
└──────────────────────────────────────────────────────────────────┘
```

**Screens never touch a DAO.** Every mutation goes through `ClinicalRepository`,
which is what guarantees three things a clinical record must always have:

1. an audit entry,
2. a sync-queue entry,
3. the DAO-level invariants (MRN allocation, note locking, derived-value
   freezing) that individual screens must not be able to route around.

`clinical/` has no Flutter dependency at all. Scoring rules are pure functions
so they can be tested exhaustively and reviewed by a clinician without reading
widget code.

### Directory map

```
lib/
├── main.dart                  bootstrap: theme, secure store, lock service
├── app.dart                   MaterialApp, lifecycle auto-lock, post-unlock DI
├── ai/                        the assistant, end to end
│   ├── assist_request.dart    sealed RequestPart (text today; files are a new case)
│   ├── conversation.dart      the thread: turns, standing intent, summary
│   ├── refinement/            fragments as changes to the standing question
│   ├── clarify/               questions asked back, and the paraphrase bank
│   ├── pipeline.dart          preprocess → interpret → authorise → execute → present
│   ├── intent.dart            sealed: Query · Report · Analysis · Rank · Overview · Mutation · Unknown
│   ├── presentation.dart      sealed: Metric · Chart · Table · Mentions · Dashboard · Proposal · Message
│   │                          each declares its honest renderings (list/table/chart)
│   ├── provenance.dart        the stage-by-stage trail behind every answer
│   ├── provenance_explanation.dart  the trail as the app's standard explain sheet
│   ├── authorisation.dart     reads allowed; writes stop at a proposal
│   ├── follow_ups.dart        the next question, as a button
│   ├── schema/                data_field (types) · clinical_tables (the vocabulary) ·
│   │                          field_registry (resolution)
│   ├── analytics/             aggregates, chart choice, robust statistics, shared periods
│   ├── records/               "who stands out": rank spec + grammar
│   ├── cohort/                clinical cohort matching, projection, published vocabulary
│   ├── interpreters/          input → intent (overview, rank, analysis, pattern, model seam)
│   └── handlers/              intent → presentation (overview composes the others)
├── clinical/                  NEWS2, age-banded reference ranges, calculations
├── core/
│   ├── app_bootstrap.dart     opens the DB *after* unlock, tears down on lock
│   ├── audit/                 append-only PHI access log
│   ├── db/                    SQLCipher handle, DDL, type helpers, app_meta
│   ├── modules/               module registry + entitlements
│   ├── routing/               go_router config
│   ├── security/              DEK manager, PBKDF2 PIN, app lock service
│   ├── session/               active clinic, signing clinician
│   ├── theme/                 JSON tokens → ThemeData, ThemeScope
│   ├── utils/                 ids, formatters, robust statistics, similarity
│   └── widgets/               SectionCard, StatusPill, VitalValue, DataChart…
├── data/
│   ├── dao/                   clinic, patient, encounter, vitals, note, attachment
│   ├── models/                immutable models with toMap/fromMap
│   ├── repositories/          ClinicalRepository
│   └── services/              attachment storage, voice recording
└── features/                  dashboard, patients, encounters, vitals, notes,
                               clinics, assist, lock, settings, shell
```

---

## 2. Security model

### 2.1 What protects what

| Asset | Protection |
|---|---|
| Clinical database | SQLCipher AES-256, page-level. The file is indistinguishable from random bytes without the key. |
| Database key (DEK) | 32 random bytes, generated on device at first launch. Held in Android Keystore / iOS Keychain. Never derived from the PIN, never leaves the device. |
| App access | Biometric prompt (biometric-only — falling back to the device passcode would let anyone who knows the phone's unlock code into patient records) with a mandatory PIN fallback. |
| PIN | PBKDF2-HMAC-SHA256, 210 000 iterations, 16-byte random salt, constant-time compare. Stored as `pbkdf2_sha256$<iters>$<salt>$<hash>`. |
| Attachment bytes | App-private storage + OS full-disk encryption. **Not** individually encrypted in round 1 — see §2.5. |
| Screen contents | `FLAG_SECURE` set unconditionally in `MainActivity`. Blocks screenshots, screen recording, *and* the recent-apps thumbnail — the last one matters most day to day. |
| OS backup | Disabled three ways: `allowBackup=false`, `fullBackupContent=false`, and a `data_extraction_rules.xml` that excludes every domain from both cloud backup and device-to-device transfer. |

### 2.2 Why the PIN is not the database key

Deriving the DEK from the PIN would be cryptographically stronger. It is not
done in round 1 because a forgotten PIN would then mean the **permanent,
unrecoverable loss of every patient record on the device**, with no path back.
That is a worse failure than the threat it defends against.

The keystore-held DEK satisfies the stated requirement — *only the application
can decrypt the database* — because the OS, not this app, enforces that no other
process can read the key.

### 2.3 Key management roadmap

The correct end state, for round 2:

1. Keep the random DEK.
2. Wrap it with a KEK derived from the PIN (PBKDF2 or Argon2id). Store only the
   wrapped DEK, so the ciphertext is useless even to an attacker who defeats the
   keystore.
3. Add a **second wrap** under an operator-held recovery key, so a forgotten PIN
   is recoverable rather than fatal.
4. Changing the PIN re-wraps; it never re-encrypts the database.

### 2.4 Lock lifecycle

The database is opened **at unlock, not at launch**. Before unlock the process
holds no key and no decrypted handle — an attacker who grabs a launched-but-
locked device gets nothing from memory either.

```
launch ──► AppLockService.initialise()
             │
             ├─ no PIN set ──────────► PinSetupScreen (first run)
             └─ PIN set ─────────────► LockScreen
                                          │ biometric or PIN
                                          ▼
                                   AppBootstrap.openAfterUnlock()
                                     · DEK from keystore
                                     · open SQLCipher handle
                                     · wire repository + session
                                          │
                                          ▼
                                       app shell
                                          │
        backgrounded ≥ 2 min ─────────────┘
                 │
                 ▼
        AppBootstrap.closeOnLock()   ← handle closed, not merely hidden,
                                       so no cached pages of PHI stay resident
```

`LockGate` sits between the router and every screen, so no code path can paint a
chart before authentication.

### 2.5 Known gaps (round 1, accepted and tracked)

| Gap | Consequence | Planned fix |
|---|---|---|
| Attachment bytes not individually encrypted | A rooted device could read clinical photos from app-private storage | Encrypt each file with a key derived from the DEK |
| No PIN-wrapped DEK | Keystore compromise exposes the database | §2.3 |
| Single local user | No per-clinician attribution on a shared device | `multiUser` module |
| Entitlements unsigned | Trivially bypassable | Ed25519-signed offline licence — and it must stay a UX gate, never a data gate |

---

## 3. Data model

Full column-level detail is in **`SystemSchema.md`**. The conventions that apply
everywhere:

| Convention | Reason |
|---|---|
| UUID v4 `TEXT` primary keys | Autoincrement integers collide the moment two offline devices sync into one backend. |
| Instants as `INTEGER` epoch ms, UTC | Unambiguous ordering across timezone changes. |
| Calendar dates as `TEXT` `YYYY-MM-DD` | A birthday must not shift when the device crosses a timezone. |
| `deleted_at` soft delete everywhere | Deleting a chart entry destroys evidence of the care that was given. |
| `updated_at` + `revision` + `sync_status` on every syncable row | Last-writer-wins with conflict detection, ready before a backend exists. |
| Derived values stored, not recomputed | BMI and NEWS2 are frozen at capture with the algorithm version, so revising the code never silently rewrites history. |

Aggregates: `clinics`, `patients` (+ `allergies`, `problems`, `medications`),
`encounters`, `vitals`, `clinical_notes` (+ `note_amendments`), `attachments`,
`audit_events`, `sync_queue`, `app_meta`.

### Migrations

`Schema.migrations` is a list-of-lists — index 0 creates v1, index 1 upgrades
v1→v2, and so on. `onCreate` and `onUpgrade` replay the same SQL, so a fresh
install and an upgraded install converge on byte-identical schemas.

---

## 4. Clinical decision support

### NEWS2

The Royal College of Physicians' National Early Warning Score 2 is implemented
in full (`lib/clinical/news2.dart`), with its published scope enforced in code:

- Validated for **acutely ill adults aged 16+**.
- **Refuses to score** children, pregnant patients, and incomplete observation
  sets — returning `null` with a typed reason rather than a number the UI might
  display. A partial NEWS2 is not a NEWS2; omitting an unrecorded parameter
  silently under-scores a sick patient.
- SpO₂ Scale 2 (target 88–92% in chronic hypercapnic respiratory failure) is
  implemented and opt-in per patient, including its non-monotonic band where a
  *high* saturation on oxygen is itself a risk.
- The algorithm identifier `NEWS2-RCP-2017` is stored on every scored row.
- Per-parameter breakdown is surfaced, so the clinician sees *what* drove the
  score rather than an opaque total.

Every band boundary is pinned by unit tests.

### Reference ranges

Age-banded (`lib/clinical/vital_reference.dart`). Paediatric heart and
respiratory rates follow the APLS/PALS bands; systolic uses `70 + 2 × age` for
ages 1–10. Values are classified `criticalLow / low / normal / high /
criticalHigh / unknown` — and `unknown` is never rendered as normal.

### Framing

All of this is **decision support**. The word "guidance" is used deliberately in
the UI strings, escalation advice always defers to local policy, and no score
overrides the clinician in front of the patient.

---

## 4b. The assistant pipeline

One path from a question to an answer, with named stages:

```
  preprocess  →  interpret  →  authorise  →  execute  →  present
```

The shape earns its keep in three specific ways.

**One implementation.** The floating bubble and the full Ask page previously
each had their own copy of the middle of this, and they drifted twice — once
over whether a counting question should list records, once over what an
unmatched question does. Anything that must be right in two places is
eventually right in one.

**Adding an output is adding a case.** A record, a chart, a table, a change
awaiting confirmation — each is a `Presentation` and a handler, not a new path
threaded through widgets. Both are sealed types, so the compiler finds every
place that has to change; adding `AnalysisIntent` surfaced four call sites that
would otherwise have been found at runtime.

**Every answer can say how it got there.** A number is the product of four
stages, and when it is wrong the useful question is which stage was wrong. The
`Provenance` trail answers that; "the AI got it wrong" does not. Its confidence
is the *minimum* across stages, not the average — an answer is only as
trustworthy as its weakest step.

The stages are also where this app's boundaries live: redaction happens before
anything could see identifiers, authorisation happens before anything executes,
and mutations stop at a proposal.

### Interpreters, in order

| Interpreter | Handles | Model? |
|---|---|---|
| `OverviewInterpreter` | "Dashboard", "how are we doing" | No |
| `RankInterpreter` | "Riskiest patients", "high BP", "top 10 by BMI" | No |
| `AnalysisInterpreter` | Aggregates, breakdowns, named charts | No |
| `PatternInterpreter` | Clinical cohorts, recall, overdue, counts | No |
| `ModelInterpreter` | The seam. Does not ship | Yes, when installed |

Most-specific first, and each declines fast; adding a capability is adding an
interpreter to this list in specificity order. The ordering is load-bearing at
the overlaps: rankings run before analysis because "patients with the highest
BMI" contains the words of a maximum ("highest BMI" alone *is* a maximum and
falls through); analysis runs before the cohort matcher because "average BP by
district" would otherwise be read as a free-text search. The cohort matcher
stays last as the broadest net.

Requests are made of sealed `RequestPart`s — all text today — and every
interpreter declares what it `canRead`, so the first non-text input (a
photographed referral, a lab PDF) is a new part case and a new interpreter,
not a rewrite of the pipeline.

### The conversation

The pipeline holds an `AssistThread` — the dialogue state shared by the bubble
and the Ask page, which are two windows onto one conversation. Expanding the
bubble adopts the answer already computed rather than re-running it; reopening
the bubble replays the thread. The thread dies with the pipeline on lock,
because a conversation about a register is PHI.

Around the interpreter chain sit four conversational stages, all coded logic:

- **Reword** — colloquial phrasings ("who should I worry about") are mapped
  onto canonical questions by a tested paraphrase bank; the rewrite is
  recorded in the provenance, never silent.
- **Refine** — a fragment with a marker ("only the women", "per month
  instead", "what about visits") is merged field-by-field onto the standing
  intent using the same extractors the interpreters use. A marker always
  means refinement; a fully-formed new question always changes the subject;
  scope-wideners ("all patients") always escape the context. The merged
  filters are shown back on the answer, so accumulated state is always on
  screen and arguable.
- **Clarify** — a half-understood question is answered with a question:
  targeted options, each a complete question the app provably answers, so
  the repair is one tap. A request carrying a measurement word that would
  otherwise fall into the free-text prose search is held back and clarified
  instead — grepping the notes for "average pressure levels" answers a
  question nobody asked.
- **Recap** — "recap" is answered from the thread itself: the summary line
  plus earlier questions as tappable suggestions. The same summary shows
  continuously as the context strip above the composer, built from the
  standing intent's own filter descriptions so it can never claim something
  the filters do not.

### The model contract

Across all three tasks the model chooses among structured options rather than
producing free text: a question from the published bank, a section number for
a sentence. Only patient-facing rewording generates prose, and it is the one
task that carries a caveat instead of a gate.


`ModelInterpreter` (last in the chain, active only when a model is installed)
is a **translator, never an author**: the model receives the redacted request
plus the published question bank and returns *a sentence* — the nearest known
question form — which then re-enters the same coded grammars, validation and
authorisation as typed text. A hallucinated rewrite fails to parse and falls
through to the clarifier; an echo of the request is refused at the engine; a
rewrite that only survives as a free-text grep is refused at the interpreter.

The runtime is llama.cpp statically linked into a four-function C shim
(`native/llm_shim/clinical_llm.c`, pinned tag, `tool/build_llm_shim.sh`
rebuilds host and Android arm64 artefacts). The shim exists because binding
llama.cpp's own structs from Dart means mirroring layouts that change between
releases — a wrong offset misreads memory rather than erroring. `LlamaEngine`
runs the blocking C calls in a dedicated isolate; the model handle never
crosses it. Models are catalogued with exact artefacts, sizes and licences in
`data/services/assist/assist_model_catalog.dart`, installed by
`AssistModelManager` through the same `.part`-staged, size-pinned download
machinery the speech models use (`model_download.dart`), and hot-swapped
through a provider so a model change never destroys the conversation.

Coded logic first, always. The schema is eleven tables with a closed clinical
vocabulary, so hand-written matching covers most of what anyone asks —
instantly, offline, identically on every device, and in a form that can be shown
back and argued with. A model belongs after this, filling gaps, and is held to
the same contract: it chooses among structured intents a human defined, and
never produces SQL, a widget, or a database call. Its output is *validated*
against the schema before it becomes an intent — a model naming a table or field
that does not exist is discarded rather than repaired.

### Rendering

`AssistPresentationView` (features/assist/presentation_view.dart) owns three
things: the dispatch over the sealed `Presentation`, the heading every answer
carries, and the follow-up strip. How each kind of answer looks lives in
`features/assist/views/`, one file per kind, sharing one table card and one
truncation footer.

Every presentation declares its honest renderings (`views`): a cohort is a
tappable list or a table, a series is a chart or a table, a scatter refuses
tabulation (a thousand unlabelled coordinate pairs is not a table). The first
is the default; the rest are a toggle in the heading. "As a table" in the
question flips the default without changing the computation. The choice
resets per answer — a preference expressed about a breakdown says nothing
about the next recall list.

An answer from the assistant is not a different kind of object from the rest
of the app and must not look like one: same panel, same rows, same explanation
control. The only thing that marks it out is the generated badge, reserved for
answers a model actually touched — badging deterministic matching as "AI"
devalues the badge where it matters.

---

## 5. Modularity and subscription

`ModuleRegistry` describes 14 modules across `core` / `professional` /
`clinicPlus`, with a dependency graph closed transitively by
`ModuleRegistry.resolve` — a licence granting `voiceNotes` implicitly grants
`attachments` and `patients`, so a licence can never grant an unusable module.

`Entitlements` currently grants everything. It exists now, exercised from the
start, because a subscription bolted on later tends to be bypassable in exactly
the places nobody tested.

**It is a UX gate, not a security boundary.** See `Features.md` §3 for why the
"unsubscribe → data stays encrypted" requirement must not be built as originally
stated.

---

## 6. Offline and sync

There is no network code in round 1. `sync_queue` is nonetheless written on
every mutation, collapsing repeated edits to one pending item via a unique index
on `(entity_type, entity_id, operation)`.

The reason to write it now: a device used offline for months before sync is
switched on must still know what changed, and that cannot be reconstructed after
the fact.

When a backend arrives it needs: a drain worker, `updated_at`/`revision`
conflict resolution, attachment upload with resume, and an encrypted transport
whose keys are *not* the local DEK.

---

## 7. Theming

`assets/theme/clinical.json` is the single source of truth for appearance.
`ThemeConfig` deserialises it into colour, typography and metric tokens;
`AppTheme` builds `ThemeData` from those tokens only; `ThemeScope` exposes the
clinical semantic colours that `ColorScheme` has no slot for.

**No widget hardcodes a colour or a spacing value.** They read
`context.palette`, `context.metrics`, `context.texts`.

Component themes are set explicitly rather than left to Material defaults, which
are more colourful and more rounded than a clinical record app should be.

The semantic triple `normal` / `caution` / `critical` maps onto **observation
severity**, never onto generic UI state — keeping that mapping in one place is
what stops "red because it's a delete button" and "red because the patient is
unstable" from ever looking the same.

---

## 8. Safety properties enforced in code

| Property | Where |
|---|---|
| Patient identity visible on every screen that can write | `PatientIdentityBar` |
| Allergy status always shown, including "not recorded" | `AllergyBanner` |
| Signed notes reject edits at the data layer | `NoteDao.update` throws |
| Amendments require a reason and chain by hash | `NoteDao.amend` |
| Signing an empty note is refused | `NoteDao.sign` |
| Encounter + note sign together | `ClinicalRepository.signEncounter` |
| Vitals copy-forward limited to height/weight | `VitalsEntryScreen` |
| NEWS2 refuses out-of-scope patients | `News2Calculator` |
| Derived values frozen with algorithm version | `ClinicalRepository.recordVitals` |
| Audit logging never blocks a clinical write | `AuditService.log` swallows |
| Audit detail carries field *names*, never values | convention, documented at the call site |
| Nothing clinical is hard-deleted | `deleted_at` everywhere |
| 24-hour clock, day-first alphabetic-month dates | `Fmt` — `03/04` is ambiguous, and on a clinical record an ambiguous date is a defect |
| Abnormal values carry a text marker, not only colour | `VitalValue` |

---

## 9. Testing

66 unit tests over the safety-critical layer:

| Suite | Covers |
|---|---|
| `test/clinical/news2_test.dart` | Every band boundary, scope refusals, risk banding, single-parameter-3 escalation, Scale 2 |
| `test/clinical/vital_reference_test.dart` | Age arithmetic, paediatric vs adult banding, unknown-never-normal |
| `test/clinical/calculations_test.dart` | BMI (including unit-slip rejection), MAP, shock index, BP staging, conversions |
| `test/core/pin_hasher_test.dart` | PBKDF2 verify/reject, salting, malformed input, iteration floor |
| `test/data/clinical_note_test.dart` | Hash determinism, tamper detection, lock semantics |
| `test/data/patient_test.dart` | Naming, identity line, search index, map round-trip, timezone-proof DOB |

```bash
flutter test        # 66 tests
flutter analyze     # clean
```

Not yet covered: DAO integration tests (need `sqflite_common_ffi` with a
SQLCipher build) and widget tests.

---

## 10. Running

```bash
flutter pub get
flutter run                       # attached device
flutter build apk --release
```

First launch asks for a 6-digit PIN, then seeds a clinic named "My clinic".
Biometrics are opt-in from Settings once a PIN exists.
