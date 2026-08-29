# Clinical Workflows — Architecture & Plan

Physician-facing features for the moments that matter most in a busy,
understaffed clinic: *who do I see first, what do I need to know, what must not
slip, and how do I record it without typing.*

This document is the contract. It is written **before implementation** because
the data is clinical and ambiguity is not tolerable: a worklist that quietly
drops a patient, a summary that renders "not recorded" as normal, or a model
that invents a value are all defects that can harm. Everything below is
designed so those cannot happen silently.

---

## 1. The core idea — four engines, not eight features

Eight requested features collapse onto **four reusable, deterministic engines**.
Build the engines once, tested exhaustively; compose the features cheaply.

| Feature | = composition of engines |
|---|---|
| Triage board | `Worklist` (acuity rule) over `ClinicalFlag`s |
| Recall / follow-up list | `Worklist` (overdue rule) |
| Open-work list | `Worklist` (unfinished-doc rule) |
| Prime-the-chart | `RecordSummary` (full pre-read) |
| Shift handoff (SBAR) | `RecordSummary` (SBAR shape) + optional model rewording |
| Safety interlocks | `ClinicalFlag`s surfaced prominently |
| Voice-first entry | `AgentSurface` + voice driver |
| Ambient scribe / Photo-to-data | `AgentSurface` + audio / image driver |

All four engines live in `lib/clinical/` — the app's home for pure logic with
no Flutter imports and full unit tests. That placement is deliberate: it is
what makes them reusable in a future project and exhaustively testable in this
one.

---

## 2. The engines

### 2.1 `Worklist` — a ranked, explainable, complete list of patients

```
WorklistRule  : (ReadModel, Clock) → Worklist     // pure, deterministic
Worklist      { id, title, asOf, entries[], considered, excluded[] }
WorklistEntry { patientId, rank, score, reasons[], provenance }
```

* **Deterministic total order.** The sort is total and reproducible: primary
  key, then documented tie-breakers down to MRN, so the same inputs always
  produce the same order. No "roughly sorted".
* **Completeness is auditable.** `considered` is the count the rule looked at;
  `excluded` records every patient left off *and why*. A missed patient is
  therefore detectable, not invisible.
* **Every entry explains itself.** `reasons` are human-readable ("NEWS2 11 —
  high", "waiting 42 min"); `provenance` names the exact rows and timestamps
  the score came from, for an InfoDot.

### 2.2 `RecordSummary` — a deterministic, sourced view of a record

```
SummaryBuilder : (Record) → RecordSummary          // pure, deterministic
RecordSummary  { patientId, asOf, sections[] }
SummarySection { key, title, items[] }
SummaryItem    { label, value, state, flag?, source }
```

* **"Not recorded" is a value, never a blank.** `state ∈ {recorded, notRecorded}`
  — an unrecorded allergy status is shown as "not recorded", never as "no
  allergies". This is the single most important honesty rule in the record.
* **Sourced.** Every item names where it came from, so the pre-read and the
  handoff are auditable.
* **Shape-agnostic.** Prime-the-chart uses the full summary; handoff selects an
  SBAR subset. Same builder, same guarantees.

### 2.3 `ClinicalFlag` — a derived, explainable warning

```
FlagRule : (Record) → List<ClinicalFlag>            // pure, deterministic
ClinicalFlag { subjectId, severity, title, reason, source }
severity ∈ { info, caution, critical }              // maps to clinical tone
```

One engine produces every warning in the app — allergy, elevated NEWS2,
possible duplicate, unsigned note past a threshold, overdue review. Flags feed
banners, the triage score, and worklists. `severity` uses the existing clinical
severity triple and is **never** borrowed for decorative UI state.

### 2.4 `AgentSurface` + drivers — already built

The removable agentic module (see the agentic docs) already gives us surfaces
(named, typed, bounded fields), drivers that *propose* into them, and
validation. Voice-first entry, ambient scribe and photo-to-data are new
surfaces and drivers on this existing contract — no new architecture.

---

## 3. Read models

Rules do **not** query the database live while computing — that would let the
data shift mid-calculation. Each engine runs over an explicit **read model**: a
snapshot assembled once through `ClinicalRepository`, stamped `asOf`.

```
TriageReadModel  { asOf, rows: [ (patient, latestVitals, arrival, flags[]) ] }
RecallReadModel  { asOf, rows: [ (patient, lastSeen, dueRules) ] }
```

A read model is pure data. The engine over it is a pure function. Together they
are trivially unit-testable against fixtures, and a given snapshot always yields
a given worklist.

---

## 4. The no-ambiguity contract (enforced by tests)

1. **Deterministic engines are the source of truth.** Every rule is a pure
   function, tested against clinical fixtures with every threshold pinned — the
   way NEWS2 bands already are. A guardrail test asserts the engines import no
   Flutter and no model.
2. **Everything explains itself.** Every rank, summary item and flag carries its
   derivation (`reasons` / `source` / `provenance`) and surfaces it through an
   InfoDot. Nothing derived is shown without a "why".
3. **Completeness is auditable.** Worklists carry `considered` and `excluded[]`;
   a test asserts `considered == included + excluded.length` so nothing can be
   dropped in silence.
4. **Not-recorded is never normal.** A test asserts `RecordSummary` renders an
   absent required field as `notRecorded`, never blank and never a default.
5. **Models never author.** A model only proposes into a validated surface, or
   rewords a deterministic summary; its output is validated against the schema
   and confirmed by the clinician, and marked as generated. It never writes a
   value or a rank on its own.
6. **One audited write path.** Everything here is read-only except the explicit
   confirm step, which goes through `ClinicalRepository` (audit + sync +
   invariants), unchanged.

---

## 5. Roadmap (dependency- and risk-ordered)

* **Phase 0 — Foundations.** The four engines as pure, tested contracts, plus
  the read models. No UI. This document's guarantees become tests here.
* **Phase 1 — Deterministic, read-only.** Triage board (first), then Recall
  list and Prime-the-chart, then louder safety flags. Zero model risk, fully
  offline, glanceable, one-tap. The biggest rush-relief, shipped first.
* **Phase 2 — Voice-first entry.** Encounter surfaces (allergy/problem/med/note)
  + voice driver, on the proven vitals pattern. Propose-and-confirm.
* **Phase 3 — Model-assisted.** Handoff rewording, ambient scribe, photo-to-data
  — strictest validation, needs the larger model, built only after the
  deterministic engines have proven the abstractions.

---

## 6. First feature — Triage board (spec)

A live board answering **"who do I see first"** for patients currently waiting.

**Read model.** All patients with an `arrived` appointment not yet `completed`
at this clinic, each with their latest vitals set and derived flags, `asOf` now.

**Ordering (total, deterministic).** In order of precedence:

1. **NEWS2 risk band**: high → medium → lowMedium → low.
2. Patients whose NEWS2 **cannot be scored** (incomplete observations, or
   out-of-scope such as under-16 or pregnant) are **not** treated as low risk.
   They appear in a distinct **"needs observations"** state, ordered by wait
   time. An unmeasured patient may be the sick one; the board must never imply
   otherwise by sorting them below "low".
3. Within a band: presence of a `critical` clinical flag (e.g. a red-flag term
   surfaced from the note) before those without.
4. Then **longest wait first**.
5. Tie-break: arrival time, then MRN — so the order is total and reproducible.

**Each row shows** the patient, their band or "needs obs", the reasons
("NEWS2 11 — high", "waiting 42 min", "red flag: chest pain"), and an InfoDot to
the exact obs and time behind it. One tap starts the visit.

**Completeness.** Every waiting patient appears exactly once; `excluded[]` is
empty by construction (a triage board that hides anyone is a defect), asserted
by test.

**Tests (before UI).** Band ordering; not-scored never sorted as low; wait-time
ordering within a band; total-order reproducibility; completeness; provenance
present on every entry. All against fixtures, no Flutter, no model.

**Placement.** `clinical/worklist/` (engine + rules), read model in `data/`, the
board screen a new feature module consuming the engine through
`ClinicalRepository`.

---

## 7. Module gating — optional per clinic (implemented)

Not every clinic triages, so a workflow feature's *presence* is a clinic
decision, not an assumption baked into the build. Two independent gates decide
whether triage exists in an install, both checked in one place
(`TriageModule.isVisible`):

* **Licensed** — `Entitlements.has(ModuleId.triage)`. What the plan allows.
* **Switched on** — `WorkflowPreferences.isEnabled(ModuleId.triage)`. What the
  clinic chose, persisted in the encrypted meta store, **default off**.

A descriptor marks itself `clinicConfigurable` to opt into this; the settings
Modules screen renders a switch for each such module. When the gate is closed,
every entry point (dashboard card, route) renders nothing, so a clinic that
does not triage never sees it — and the `lib/features/triage/` folder can be
lifted out without touching another feature. This is the containerization the
four engines were built to allow: a workflow is a thin feature module over pure
engines, present only when wanted.

## 8. Open questions to settle before the next feature

* Recall "overdue" definitions — which review cadences, from where (per-problem
  policy vs a flat rule)? Needs a clinician's input; it must be data, not a
  hardcode.
* Handoff format — SBAR exactly, or a local variant?
* Whether triage should factor a manual acuity override a nurse can set (and how
  that is audited).
