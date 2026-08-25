# Features

Status legend: **Built** = implemented and working in the app · **Scaffolded** =
data model, storage and service layer exist, UI is minimal · **Interface only** =
the seam is defined and nothing depends on it yet.

---

## 1. Clinical features

### 1.1 Patient register — *Built*

| Capability | Notes |
|---|---|
| Registration | Four required fields only: given name, family name, sex at birth, and either a date of birth or an approximate age. Everything else is optional and can be completed later. |
| MRN allocation | Six-digit, zero-padded, allocated inside the insert transaction so two rapid registrations cannot collide. Human-quotable over a phone. |
| Approximate age | Patients who know their age but not their birth date get a derived 1 January date flagged `dob_is_estimated`. The chart shows `~34y`, never a birthday the record cannot support. |
| Sex at birth vs gender identity | Stored separately. The former drives reference ranges and dosing; the latter drives how the patient is addressed. |
| Search | Token-AND over a denormalised lowercase index covering name, MRN, phone and national ID. Every term must match, so `john 98` narrows. 180 ms debounce. |
| Recency | Patient lists default to most-recently-seen first — on a shared clinic device this is almost always what the user wants. |
| Next of kin | Name, phone and relationship, for when the patient cannot consent. |

### 1.2 Clinic selection — *Built*

Multi-site by design: a locum working three sites files encounters against the
right one. Selection is sticky across launches, changeable in one tap from the
dashboard app bar, and stamped onto every encounter. Clinics are soft-archived,
never deleted, so historic encounters keep pointing at where care happened.

### 1.3 Vital signs — *Built*

- **Field order follows the NEWS2 observation chart** — respiration, saturation,
  oxygen, blood pressure, pulse, consciousness, temperature — because that is
  the order the observations are physically taken in.
- **Age-banded reference flagging.** Paediatric heart and respiratory rate bands
  follow the APLS/PALS age groups; systolic uses the `70 + 2 × age` fifth-centile
  approximation for ages 1–10. A pulse of 140 reads *normal* in a six-month-old
  and *critically high* in an adult.
- **Live NEWS2 during entry**, not after saving — a deteriorating patient is
  flagged while the clinician is still at the bedside.
- **Derived values computed once and stored**: BMI, and NEWS2 together with its
  algorithm version. A historic row keeps the meaning it had when recorded.
- **Copy-forward is limited to height and weight.** Copying a previous blood
  pressure would put a number on the chart that nobody measured.
- Captured: BP (+ position, MAP, pulse pressure), pulse, respiratory rate,
  SpO₂ (+ oxygen flow and delivery), temperature (+ site), ACVPU consciousness,
  height, weight, BMI, head circumference, pain 0–10, capillary refill, blood
  glucose.
- Colour is never the only signal — every abnormal value also carries an
  `H`/`L`/`HH`/`LL` marker.

### 1.4 Patient encounter — *Built*

Visit types (new, follow-up, emergency, procedure, telehealth, home visit,
antenatal, immunisation), presenting complaint in the patient's own words with
one-tap common complaints, disposition, referral target, follow-up date, and
clinician attribution. Encounters are `draft → in progress → completed → signed`;
`signed` and `amended` are terminal for editing.

### 1.5 Clinical note — *Built*

- **SOAP structure**, four sections stored separately because they are read
  separately — on a follow-up the clinician jumps straight to the last
  Assessment and Plan.
- **Autosave** on a 900 ms debounce. Consultations get interrupted; nothing is
  lost to a missed save.
- **Six templates** (blank, general consultation, follow-up review, acute
  presentation with an ABCDE skeleton, antenatal, procedure). Templates only
  fill *empty* sections — they never overwrite what a clinician wrote.
- **Copy forward** pulls the previous signed assessment and plan in, stamped
  `Carried forward from <date>:` so it never reads as fresh observation.
- **Sign and lock**: SHA-256 over canonical content is stored at signing. The
  editor shows an integrity banner and turns red if stored text ever diverges
  from the signature.
- **Amendments** append with a mandatory reason and chain by hash, so removing
  one from the middle of the chain is detectable. Enforced in the DAO, not just
  the UI — a locked record stays locked whichever screen calls in.

### 1.6 Supporting clinical lists — *Built*

| List | Why it is in round 1 |
|---|---|
| **Allergies** | Three-state status: *not recorded* / *no known allergies* / *has allergies*. All three are displayed — a blank space reads as "no allergies" to a hurried clinician, and that assumption is how a patient gets given a drug they react to. Severe and anaphylactic reactions render a full-width red banner on every screen for that patient. `refuted` status preserves history for mis-reported allergies. |
| **Problem list** | The running summary read first to understand who is about to walk in. Active/resolved/inactive, chronic flag, optional ICD-10 code. |
| **Medications** | Rendered as a prescription-style sig line (`Amoxicillin 500 mg PO TDS × 5 days`). Route and frequency are one-tap chips from the common set. |

### 1.6b Appointments and the calendar — *Built*

Day, week and month views over one date-range query. The month grid shows load
rather than detail — a count and a density bar per day — because at that size a
grid of appointment titles is both unreadable and uncrowdable, and the question
a month view answers is "which days are heavy". Tapping a day moves the day
list, which is where detail belongs. On a tablet the calendar and the day list
sit side by side; on a phone the calendar is a fixed header above the list, so
choosing a day and working it are never separated by a mode switch.


The front-desk workflow, modelled as it actually runs: booked → arrived →
in progress → completed, with `noShow` and `cancelled` as first-class outcomes.

| Capability | Notes |
|---|---|
| Booking | Date, time, length, type, reason. Four decisions — anything longer and the desk books on paper instead. |
| Conflict detection | Overlaps are shown as a warning, never a block. Double-booking is sometimes correct and the software should not overrule the person at the desk. |
| Day list | Time-gutter timeline with per-patient colour, arrival state and live wait times. |
| Check-in | One tap to mark arrived; the waiting room sorts by longest wait, which is the order people expect. |
| Start visit | Converts a booking into an encounter and links the two, so the schedule shows what came of each slot. |
| Did-not-attend | Recorded rather than deleted — a patient missing three reviews is a safety signal that only exists if the misses were kept. |

### 1.6c Inline attachments — *Built*

Evidence lives next to the text it belongs to, not on a separate screen.

- **Voice notes play inline**, under the exact SOAP section they were dictated
  into, with scrub position and duration.
- **Photos** appear as thumbnails inline; tapping opens a pinch-zoom viewer
  **rendered in-app**. Clinical images are deliberately never handed to the
  system gallery — that copies PHI out of the sandbox where retention and
  backup are no longer controlled.
- **Documents** show as labelled cards with size and date.
- Capture (camera, gallery, file, dictation) is on each section's header, so a
  wound photo is taken while examining the wound.
- **Known gap:** PDFs are listed but not yet rendered in-app. Handing them to
  an external viewer would leak PHI, so in-app rendering is the tracked fix
  rather than a quick `open_file` call.

### 1.6d Contacting patients — *Built*

Call and SMS buttons on the chart, the app bar and next of kin. The number is
handed to the platform dialler rather than dialled directly, so a mis-tap in a
list never rings a patient.

### 1.7 Dashboard — *Built*

Ordered by what is actually pending, with reference numbers last — "registered
patients" is context, not a task:

1. **Next up** — a full-width card for the next patient, or whoever is already
   waiting, with *Start visit* one tap away.
2. **Quick actions** — new patient, book visit, waiting room (with a live
   count badge), find patient. Fixed positions, so they become muscle memory.
3. **Needs a second look** — patients with NEWS2 ≥ 5 today. The section
   *disappears* when empty; an always-present "nothing to see" card trains
   people to stop looking where warnings appear.
4. **This week** — compact stat chips plus a seven-day encounter bar chart.
5. **Today's clinic** — the next few booked slots.
6. **Unfinished charting** — open and unsigned encounters with section progress.
7. **Recent patients** for fast chart re-entry.

Patient rows carry a stable per-chart avatar colour derived from the record id,
so a long list is scannable. The colour is deliberately non-semantic — clinical
meaning is reserved for the severity palette.

### 1.8 Attachments and dictation — *Built*

Photo and document capture have full model, storage and service support
(SHA-256 digest, orphan reclamation, body-site tagging for serial wound
comparison).

**Dictation** is a full pipeline rather than a mic button:

| Stage | What happens |
|---|---|
| Capture | 16 kHz mono PCM, streamed rather than encoded to a file — owning the samples is what makes everything below possible |
| Trim | Energy-based voice activity detection removes the unspoken stretches. Typically 30–50% of ordinary dictation |
| Transcribe | Whisper tiny (int8) via sherpa-onnx, in a spawned isolate, entirely on the device |
| Re-transcribe | Any recording already on a note can be transcribed later, so audio captured before a model was installed is not text-less forever |
| Retake | Start over mid-recording without leaving the sheet — a stumble in the first sentence otherwise costs three taps to undo, which is enough friction that people keep a bad recording and fix it in text |
| Review | The transcript is shown for editing and is **never** inserted without a tap |
| Attach | The trimmed audio is attached to the note regardless of what happens to the text |

The trimming is deliberately biased toward keeping audio: clipping a word is
unacceptable, keeping half a second of room tone is merely wasteful. Every
parameter follows from that — a quarter-second of pre-roll emitted
retroactively, 420 ms of hangover, and a 60 ms sustained-run requirement so a
dropped pen is not dictation. Two failure modes are tested explicitly because
both destroy data: a recording with no pauses must not be deleted as silence,
and a loud clinic room must not be kept as speech.

Stored as 16-bit WAV, uncompressed. That is a real cost — roughly 1.9 MB per
minute of *speech* at full quality, or 0.9 MB in compact mode — and it is paid
because no compressed format can be both fed to the recogniser and played back
without a codec the device may not have. Trimming pays for part of it; the
transcript pays for the rest, since audio that has become text is rarely opened.

### 1.9 Explaining what the app worked out — *Built*

Every derived value on screen carries an `InfoDot` opening a sheet with the
method, the inputs for that specific record, a confidence class and a caveat.
Covers NEWS2 (full per-parameter breakdown — the scores were already computed
and discarded), age-banded reference flags, MAP, BMI, trends, dashboard counts,
the "needs a second look" criteria, wait estimates, duplicate warnings and
silence trimming.

The confidence class matters most: `validated` for a published instrument,
`measured` for a fixed formula, `heuristic` for a rule this app invented, and
`insufficientData` when the figure cannot yet mean anything. A heuristic's own
explanation says in plain words that it carries no evidence base.

### 1.10 On-device analysis, no model required — *Built*

Deterministic, instant, offline, and identical on every device. Dictionary
matching, string similarity, robust line fitting and medians — no inference,
which is what makes each one explainable to the clinician being asked to act on
it. All pure Dart in `lib/clinical/insights/`, all unit-tested.

| Feature | What it does | Why it is not a model |
|---|---|---|
| **Silence trimming** | Removes unspoken audio | An energy gate decides every 20 ms on six-year-old hardware |
| **Duplicate patient detection** | Offers existing records that may be the same person at registration | Jaro–Winkler with clinical field weighting. Handles transpositions, swapped name fields and transliteration variants |
| **Deterioration trends** | Flags a vital sign moving the wrong way across visits | Theil–Sen median-of-slopes, so one bad reading cannot invent a warning |
| **Note term extraction** | Offers problems, medications and follow-up dates found in written or dictated text | Fixed dictionaries plus negation handling |
| **Wait estimates** | Tells a waiting patient roughly how long | Median of this clinic's own completed consultations |
| **Attendance estimate** | Suggests who would benefit from a reminder call | This patient's own attendance history only |

Three of these carry constraints that are part of the feature rather than
footnotes:

* **Duplicate detection never blocks registration.** The patient is at the desk.
  A check that can refuse gets defeated within a week — usually by misspelling a
  name on purpose, producing the very duplicate it was meant to prevent.
* **An allergy is never filed from parsed text.** A wrongly recorded allergy
  removes a treatment option, usually permanently, because nobody downstream
  feels safe deleting one. Extraction requires an explicit "allergic to", and
  accepting the suggestion opens the full form so severity and reaction are
  asked.
* **The attendance estimate is for offering support, never withholding it.** It
  uses no age, sex, address or any other characteristic — only this patient's own
  past appointments. A model that learns which neighbourhoods miss appointments
  reproduces the inequality that created the pattern and dresses it as
  arithmetic.

### 1.10b Asking the register questions — *Built*

A search box that answers questions about the patients on the device: recall
lists, overdue follow-up, clinic activity and cohort counts.

It understands six tables, and a word in the question chooses which:

| Table | Holds | Example |
|---|---|---|
| `patients` | The register, with problems, medicines and allergies as filters | "everyone on warfarin" |
| `appointments` | Booked slots, including cancellations and non-attendance | "appointments cancelled this month" |
| `visits` | Consultations that actually happened | "how many visits last month" |
| `vitals` | Observation sets and the score calculated at the time | "observations with news2 above 5" |
| `notes` | Clinical notes, including unsigned drafts | "unsigned notes" |
| `files` | Photos, documents and recordings | "photos from last week" |

Appointments and visits being separate is not pedantry — "appointments last
month" counts what was **booked** and "visits last month" counts what
**happened**, and in a clinic with many non-attenders those are very different
numbers.

The access log is deliberately **not** reachable from here. Who opened which
record is reviewed in Settings › Access log, where the act of reviewing it is
itself recorded — routing that through a search box would quietly bypass the
audit trail that makes the log worth keeping.

The vocabulary is **published rather than hidden**: a schema reference lists
every searchable field, the phrasings that reach it, the underlying column, and
what it will *not* find. A natural-language search that cannot say what it knows
is a guessing game — the user tries phrasings until something works and has no
way to tell a question the app cannot answer from one it answered wrongly. The
router and the guide read the same word lists, and a test asserts that every
phrase the guide advertises actually routes, so what is taught and what works
cannot drift apart.

**No SQL is ever generated.** A typed phrase is matched onto a set of filters
that a human wrote and a test suite checks, and the query that runs is one of a
handful of hand-written statements in `data/dao/cohort_dao.dart`. When a small
language model is installed it plugs in beside the pattern matcher as a second
router and is held to the same contract: it returns a `CohortQuery`, never a
string of SQL.

That constraint is the whole feature, and the reason is specific. A wrong
transcript is read by the clinician who dictated it. A wrong recall list is read
by nobody — the reason for running it is that nobody could assemble it by hand —
so a list that quietly misses three patients is indistinguishable from a correct
one. Choosing among safe queries is classification, which small models do
reasonably; writing SQL is generation, which they do badly, and here being wrong
is invisible.

What follows from that:

- **Every answer shows its filters**, in clinical English, above the result. A
  misread question is therefore visible; a wrong query is impossible.
- **It refuses rather than guesses.** An unmatched question says so and offers
  examples, instead of answering a slightly different question.
- **Partial matches say so**, with the parts it understood listed.
- **A truncated list is never presented as complete** — the true total is
  counted separately from the displayed rows.
- **Deceased patients are excluded** unless explicitly included.
- **A failed question teaches**, offering phrasings built from the part of the
  question that *was* understood rather than a fixed example list.
- **Filler is ignored.** "All patients", "every single patient" and "could you
  please show me all the patients" are one request. Whether a question asks for
  a whole table is decided by *subtraction* — if nothing meaningful remains once
  quantifiers and table words are removed — which is what stops "all the
  weather" returning the entire register.
- **It reads like a colleague, not a validator.** "Not understood" is a machine
  telling a clinician they typed wrong; "I'm not sure what to search for there —
  here are some questions I do understand" is someone helping. The information
  is identical and only one of them gets used twice. The wording lives in
  `assist_reply.dart` so it can be tested rather than scattered through widgets.

#### Telling people it exists

A capability sheet, behind one button on the Ask page and one in the bubble,
lists what can be asked in three tabs: clinical starters grouped by *purpose*
(safety, falling out of care, today and this week, reporting), chart questions
per table, and every field with the words that reach it.

It is behind a button because it used to be permanently on screen, and
permanently is exactly wrong for a guide: nobody reads it twice, and sitting in
the same cards as the answers it was indistinguishable from them, so the page
looked like it was always showing results.

Everything in it is a button, because **a tap is better input than a remembered
phrase** — it hands the interpreter an unambiguous question instead of leaving
it to infer one. Nothing in it is hand-written prose about what *might* work:
the clinical starters come from `QueryVocabulary`, the chart questions are
generated from `FieldRegistry`, and tests walk every one of them through the
parser, so the sheet cannot advertise a question the app does not answer.

Answers carry **follow-up buttons** for the re-cuts that apply to that
particular answer: a cohort offers "By age" / "By sex" / "Per week", a chart
offers "Show the list", "Median", "Per month". A cut *replaces* the previous one
rather than stacking, so tapping through three follow-ups gives
`visits this month by age band`, not a phrase that matches only its first
fragment and silently ignores the rest.

Starters load the box for editing; follow-ups run immediately. A starter is a
draft of a question — the useful version is almost always narrowed. A follow-up
refines an answer already on screen, and making someone confirm "show the list"
defeats the point of offering it.

Reachable from anywhere via a floating assistant bubble, which answers in place
and can hand the question to the full screen when the result outgrows it.
Draggable, because there is no safe corner: wherever it defaults to, it will
sooner or later sit on the one control someone needs. Switchable off in
Settings.

The bubble is mounted above the router's Navigator so it survives every route —
which also leaves it with no `Overlay` of its own, so it carries one. Without
it every tooltip inside threw and the bubble rendered as a red error box.

The SQL is tested against a real SQLite database rather than by asserting on
strings, because well-formed and *right* are different properties. The cases
that matter: a dose in the drug-name field must not drop a patient from a
recall (`Warfarin 3mg` is found by `warfarin`), a `_` in a search term must not
become a wildcard, a stopped prescription must not appear, a resolved problem
must not keep someone on an overdue list, a never-seen patient must appear on
one, and the count must always agree with the list.

### 1.10bb Charts, statistics and arbitrary aggregates — *Built*

Beyond cohort lists, any number in the register can be counted, averaged or
plotted against any category — "average waiting time by clinician", "systolic BP
against age", "spread of BMI", "visits per month".

This works from a **semantic schema registry** (`ai/schema/field_registry.dart`)
that describes every table and column the way a person would ask about it: what
kind of thing it holds, what unit it is in, and the words that reach it. People
do not say `systolic_bp`; they say blood pressure, BP, systolic, or top number.
A registry that only knew column names would answer almost nothing.

| Kind | Means | Examples |
|---|---|---|
| Numeric | Can be averaged, summed, correlated, binned | `spo2` ("sats", "saturation"), `wait_minutes` ("waited", "door to doctor") |
| Categorical | Groups into bars or slices | `provider_name` ("clinician", "who saw them") |
| Temporal | Becomes an axis, buckets into days/weeks/months | `scheduled_at` ("booked for", "when") |
| Boolean | Groups like a category, never averaged | `on_oxygen` |
| Text | Searchable, never plottable | `chief_complaint` |

The distinction is not the SQL type. `news2_score`, `pain_score` and `on_oxygen`
are all `INTEGER`; averaging the first two is meaningful and averaging the third
is nonsense.

**Derived fields** are first-class: patient age from a date of birth,
consultation length from two timestamps, waiting time from arrival to start,
time-to-sign on a note. Each is computed in Dart from the columns it names, with
implausible values discarded — a "visit" spanning three days is a record left
open, not a long consultation, and averaging those in makes every clinic look
slow.

#### What is drawn, and why

The chart is chosen from the shape of the data rather than asked for, because
the person asking usually knows what they want to know and not which chart shows
it. A named shape ("as a pie chart", "line graph") overrides it.

| Situation | Chart | Reason |
|---|---|---|
| Two numeric fields | Scatter | The question is whether they move together, and nothing else shows that |
| A timeline | Line, or area for counts | |
| 2–6 categories that sum to a whole | Donut | Shares read best as a ring — but **only** where the parts genuinely sum to the total. An average per category does not, so it is never drawn as one |
| Anything else categorical | Bar | |
| One numeric field, no grouping | Histogram | The spread is what a mean hides |

#### What it refuses to draw

- **A gap stays a gap.** A month with no visits is drawn as a break in the line,
  not joined across — a straight line over an empty month claims a steady rate
  through it. And an *average* over an empty bucket is unknown, not zero;
  drawing it as zero invents a crash that never happened.
- **A long tail is folded, never cut.** Categories past the twelfth become
  "Other (n)", preserving the total, because a chart whose parts no longer add
  up to the number printed above it is the fastest way to lose a reader.
  Only counts and sums are folded — an average of averages is not an average, so
  for anything else the tail is counted rather than combined.
- **A missing reading is not a reading of zero.** Rows with nothing recorded are
  excluded and *reported*: "average BMI 24.1" over six of two hundred patients
  is a different claim from the same number over all of them.
- **Prose is never a dimension.** One bar per record is a table drawn badly.

#### Statistics that travel with the picture

Every chart carries mean, median, quartiles, range and standard deviation, plus
Pearson's *r* on a scatter and a Theil–Sen trend on a timeline. A bar chart shows
which category is biggest; it does not show that the spread is so wide the
ordering is noise, or that four fifths of the rows were empty.

Three specific choices:

- **Theil–Sen, not least squares.** One catastrophic week — a clinic closed, a
  device broken — swings a least-squares line hard enough to invert the reported
  direction. Shared with the vitals deterioration check in
  `core/utils/robust_stats.dart`, which needs the same property for the same
  reason.
- **Tukey's fences for outliers, not a standard-deviation rule.** A
  transcription slip — 1800 mmHg for 180 — inflates the very deviation that
  would have caught it.
- **Correlation states strength, never cause.** "A moderate relationship" and
  the caveat that a register is not an experiment; anything affecting both
  variables produces the same picture.

Direction is read as news where the field has one: for a waiting time or an
early-warning score, "rising" and "getting worse" are the same fact and the
reader should not have to work that out. For a count of visits, rising is
neither, and nothing is claimed.

#### The same safety property

**No identifier in any statement comes from what was typed.** A question selects
entries from the registry; the DAO reads `DataTable.name` and `DataField.columns`
off those entries. A phrase matching no registry entry produces no query at all,
so the failure mode is "I do not know that field" rather than a surprising
statement. Every value is bound as a parameter.

Matching is deliberately strict — a fuzzy score below 0.90 is treated as a
coincidence rather than a synonym. Charting a neighbouring column is worse than
declining, because a wrong chart is confidently wrong and nothing on screen
contradicts it.

The DAO returns *rows*, not aggregates. The register on one device is small, and
one pass over the two or three columns an analysis touches buys the median, the
quartiles, the spread and the outliers that separate SQL aggregates cannot give
together — all of it in code testable without a database.

### 1.10bc Who stands out — rankings, thresholds, and "high BP" — *Built*

The third question shape, after cohorts ("who matches") and analyses ("what is
the shape"): **pick people by a measured value**. "Riskiest patients",
"patients with high BP", "top 10 by BMI", "febrile patients", "news2 above 5".

Three rules make it honest:

- **"High" means a published number.** Each measure carries its NEWS2/NICE
  screening cut-off in the schema registry; the qualifier is only accepted
  where one exists ("high age" is refused), and every answer states the
  number it applied — "high BP" read as 140 mmHg or more.
- **One extreme per patient.** A patient with five readings is five rows, and
  ranking rows would fill the list with whoever was measured most often. Rows
  fold to each patient's single worst value, and the answer says which reading
  it kept and when.
- **Measured, never diagnosed.** "Patients with high BP" is the measured;
  "hypertensive patients" is the problem list — deliberately different words
  routed to deliberately different engines, because the two lists disagree in
  exactly the ways a clinician needs to see. The headline says so.

Results are the same tappable people every other list shows, with the measured
value as a column one toggle away.

### 1.10bd Projection, views, and the dashboard — *Built*

**Projection** — "patients and their contact numbers", "phone numbers of all
patients" — peels the "and their X" off before the cohort router runs, so it
changes what the table *shows*, never who is on it. Only patient attributes
project (in "patients with diabetes", "diabetes" resolves to no attribute, so
it stays a filter), a half-resolved list declines entirely rather than
silently showing fewer columns, and each field formats its own cells so the
same value cannot read differently in two places.

**Views** — every answer declares its honest renderings and the heading grows
a toggle when there is more than one: a cohort is a tappable list ⇄ a table, a
series is a chart ⇄ a table. A scatter refuses tabulation. "As a table" in the
question flips the default without changing the computation; asking for
columns implies it.

**Dashboard** — "clinic dashboard", "how are we doing" composes four ordinary
answers (visits per week, appointments by outcome, highest early-warning
scores, unfinished notes) through the ordinary handlers, so a tile can never
disagree with the same question asked alone and every tile keeps its own
explanation and caveats.

### 1.10be A conversation, not a search box — *Built*

The assistant now carries state between questions, on both surfaces at once:

- **Refinement.** "Everyone on warfarin" → "only the women" → "what about
  visits" is one conversation, each fragment merged onto the standing
  question. The merged filters are always shown back, and the context strip
  above the composer says what the conversation currently is. "All"/"everyone"
  words escape the context; a fully-formed new question changes the subject;
  ✕ or the panel's restart ends the topic explicitly.
- **Clarification.** A half-understood question gets a question back, with
  tappable options that are each a complete question the app provably
  answers. "Average pressure levels" is never grepped through the notes — it
  is held back and asked about.
- **Paraphrases.** "Who should I worry about" lands on "riskiest patients"
  via a tested bank; every rewrite appears in the provenance trail.
- **Recap.** "Recap" replays the conversation as tappable questions; the
  thread also drives the summary strip.
- **One thread, two windows.** The bubble and the Ask page share the thread;
  expanding the bubble adopts the computed answer instead of re-running it,
  and reopening the bubble replays the conversation. Locking the app destroys
  the thread with everything else decrypted.
- **The model slot runs.** Settings › On-device AI installs a quantised GGUF
  (Qwen2.5 1.5B/0.5B, Gemma 3 1B, Llama 3.2 1B, SmolLM2 360M — exact sizes
  and licences in `assist_model_catalog.dart`; airgapped `adb push` path
  included). Inference is llama.cpp statically linked into a four-function C
  shim (`native/llm_shim`, pinned tag, rebuilt by `tool/build_llm_shim.sh`),
  run in its own isolate so a multi-second answer never blocks the UI. The
  model translates unmatched wordings into the published question bank — a
  sentence, re-parsed by the same grammars, refused if it echoes the request
  or only survives as a text grep. The contract is verified by live
  host-inference tests (`llama_engine_live_test.dart`) against the real shim
  and a real model. Swapping models never loses the conversation: the
  pipeline reads the engine through a provider.

### 1.10c Searching the narrative — *Built*

Structured filters answer the question; free-text search of note bodies and
presenting complaints is the safety net for what they cannot cover, shown as a
separate **"Also mentioned in notes"** list and never added to the count.

This exists because of an asymmetry the first version got wrong. Over-matching
and under-matching were treated as equally bad; for a recall list they are not.
An extra patient to check costs a moment. A **missed** patient on a warfarin
recall is the exact harm the list was run to prevent — and medication and
problem lists drift out of date while the narrative stays rich, so the people
most likely to be missed are precisely the ones only the notes know about.

Two things keep it from becoming noise, and both are tested:

- **Denials are dropped.** "No history of warfarin" never appears on a warfarin
  list. The judgement is the same `NoteIntelligence` negation check the note
  extractor uses, so there are not two answers to one question.
- **The sentence comes with it.** Every hit shows the surrounding text, so
  "father takes warfarin" is dismissed at a glance. A bare name on a secondary
  list would be worse than no list, because it would be believed.

### 1.10bf The model in the note editor — *Built*

The installed model's other two tasks, both in the note editor, both gated:

- **Sort into S·O·A·P.** A dictated consultation lands in Subjective as one
  block; with a model active, a button sorts it into the four sections. The
  gate is mechanical and absolute: every word of the draft must be a word the
  clinician said (a new drug name, a new number, a new "not" are corruption
  wearing tidiness), and dropping more than a third of the content refuses
  the whole draft — checked in code (`note_drafting.dart`), before the
  preview, which is itself accepted or discarded as a whole. Other sections
  are appended to, never overwritten: text a person placed is not the
  model's to rearrange.
- **Explain for the patient.** Rewords the plan as instructions a patient can
  follow. Rewording cannot be gated word-by-word — new words are the point —
  so it gets the weaker mechanical checks (an echo is refused, an essay four
  times the plan is refused as invention) and carries its caveat and badge
  into the preview, with copy or append-under-the-plan as the only exits.

Both buttons exist only while a model is installed; the note editor is
unchanged without one.

### 1.11 A small language model — *Interface only, deliberately*

`LanguageModelEngine` in `data/services/assist/` defines the seam and ships no
implementation. The interface exists now because the constraints it encodes are
easier to hold before a model arrives than to retrofit after: every output is a
draft with no path to a signed note, the model receives the text being worked on
rather than a patient record, and it must run on the device or be refused.

Nothing depends on it. The deterministic features above are the product; a model
would only ever add to them. The tasks defined are all *rewriting* — reshaping
dictated prose into SOAP sections, turning a plan into patient-facing
instructions — because a model small enough to fit is good at reshaping text it
was given and unreliable at anything needing knowledge.

---

## 2. Technical features

| # | Requirement | Status | How |
|---|---|---|---|
| 1 | Fully encrypted DB | **Built** | SQLCipher (AES-256, page-level) via `sqflite_sqlcipher`. Key is 32 random bytes generated on device, held in Android Keystore / iOS Keychain. Without it the file is indistinguishable from noise. |
| 2 | Biometric lock, PIN fallback | **Built** | `local_auth` biometric-only prompt; PBKDF2-HMAC-SHA256 PIN at 210 000 iterations. A PIN is *mandatory* — biometrics fail with gloves or wet hands, and a clinician locked out mid-consultation is a safety problem. 8-attempt throttle; auto-lock 2 minutes after backgrounding. |
| 3 | Subscription gating | **Scaffolded, deliberately** | 14 modules across 3 tiers with a dependency graph. Round 1 grants everything. See the warning in §3 below — the "otherwise the data stays encrypted" idea must not be built as stated. |
| 4 | Offline-first | **Built** | There is no network code at all. Every write also enqueues into `sync_queue` from day one, because a device used offline for months before sync is switched on must still know what changed — that cannot be reconstructed after the fact. |
| 5 | Modular and scalable | **Built** | Feature-first tree, DAO → repository → controller → screen. Every mutation goes through one repository so audit + sync + invariants cannot be bypassed. |
| 6a | Live data validation | **Built** | Plausibility is checked on every keystroke and catches unit slips — Fahrenheit in a °C field, metres in a cm field, grams in a kg field, mg/dL in an mmol/L field, a swapped BP pair. Crucially these **warn, never block**: an abnormal value is a clinical finding, and a form that refuses the sickest patients' observations is worse than one that accepts a typo. Only physically impossible values (SpO₂ > 100%) hard-block. |
| 6 | Fast data entry | **Built** | Numeric keypads open immediately; select-all-on-focus so correcting a mistyped value is one tap; units inside the field; chips instead of dropdowns; 0–10 pain as tap targets (a slider cannot be hit with a gloved thumb); autosave everywhere. |
| 7 | Device-local storage | **Built** | No backend exists and none is contacted. |
| 8 | Phone and tablet | **Built** | Three layouts chosen by available *width*, not device class: bottom bar, collapsed rail, extended rail. Master–detail two-pane for Patients and Schedule; two-column bodies for the dashboard, chart, note editor, encounter and vitals entry. A landscape tablet uses its width instead of showing a narrow strip between two empty margins. On the vitals form the live NEWS2 score is pinned above the scroll, because in landscape with a keyboard up there is barely 300 logical pixels of form visible and a deteriorating patient's score must not scroll out of view mid-entry. |
| 9 | Quick entry, attachments, voice | **Built** | See §1.8. |

### Appearance requirements

| # | Requirement | How |
|---|---|---|
| 1 | Standard clinical appearance | Muted teal primary, neutral greys, flat surfaces, hairline borders. |
| 2 | Theme from a file | `assets/theme/clinical.json` is the single source of truth. No widget hardcodes a colour or a spacing value; they read tokens through `context.palette` / `context.metrics`. |
| 3 | Standard, not colourful | Colour is reserved for clinical severity. `normal`/`caution`/`critical` map to observation severity, never to generic UI state — so "red because delete" and "red because unstable" can never look alike. |
| 4 | Minimal gradients | None used. Elevation is 0; separation is by border. |
| 5 | Useful dashboard | See §1.7. |

---

## 3. One requirement that needs changing

> *"if the user is subscribed then they have the ability to access the data,
> otherwise the data remains encrypted"*

**Do not build this as written.** Withholding a decryption key for non-payment
means an expired card can make a patient's allergy list unreadable at the moment
someone is prescribing for them. That is a patient-safety failure and, in most
jurisdictions, an unlawful denial of a patient's own health record.

What is built instead: **subscription gates features, never records.** Locking
`analytics` or `cloudSync` is fine. Read access to existing clinical data is
always available. The commercially equivalent, safe lever is to gate *new*
writes and premium modules while leaving the existing record readable and
exportable. `Entitlements` is explicitly documented as a UX gate, not a security
boundary.

---

## 3b. The one network request

There is still no network code in the application, with a single contained
exception: `SpeechModelManager` downloads the Whisper model files when a user
taps Install in Settings › Dictation.

It fetches public, static model files. It sends no patient data, no identifier
and no telemetry — the request carries a file name. It runs only on an explicit
tap, behind a dialog that states exactly this.

Transcription itself opens no socket. Once the model is installed the app is
offline again.

### The permission, and how to give it back

`android.permission.INTERNET` is declared in the main manifest solely for that
download. It is worth being precise about what it costs: **without that line the
release APK provably cannot open a socket, and an auditor can verify that from
the manifest alone rather than having to trust the code.** With it, they have to
read the code.

Two provisioning routes exist so that deleting the line remains practical, and
both are first-class rather than fallbacks:

| Route | How | Needs |
|---|---|---|
| **Push** | `./tool/fetch_speech_model.sh --push` copies the model into `/sdcard/Android/data/<package>/files/speech_models/<model-id>/`, which the app searches on launch | Nothing — `adb` writes there without root, and an app reads its own external directory without a runtime permission |
| **Load from a file** | Settings › Dictation › Load from a file, multi-selecting all three files | Nothing |

Every copy is removable from Settings › Dictation regardless of how it arrived.

### What it costs

The sherpa-onnx runtime ships native libraries per ABI. Building all four turns
a ~60 MB APK into a ~130 MB one, so `tool/install.sh` builds arm64 only — every
Android phone sold in the last several years is arm64, and the other three ABIs
buy nothing on a device you are holding. A store release wanting wider reach
should use `--split-per-abi` rather than a universal APK.

The model itself is ~104 MB (Whisper tiny.en, int8: a 12.9 MB encoder, an 89.9 MB
decoder whose size is dominated by the 51 865-token embedding matrix, and 0.8 MB
of tokens) and is **not** bundled. Shipping it would put a binary blob in the
repository, add 104 MB to every download including for users who will never
dictate, and make it undeletable.

The alternatives were measured rather than assumed: fp32 Whisper tiny.en is
152 MB, and Moonshine tiny int8 — nominally the lighter, faster option — is
124 MB across four graphs. int8 Whisper tiny.en is the smallest of the three
that keeps offline English accuracy usable for dictation.

---

## 4. Round 3 candidates

Ordered by clinical value per unit of work:

1. **PDF referral letter / record export** — the most-requested output in real practice.
2. **PIN-wrapped DEK + recovery wrap** — see `SystemArchitecture.md` § Key management roadmap.
3. **Per-file attachment encryption** — closes the one gap where bytes are protected only by the OS sandbox.
4. **Drug–allergy interaction check at prescribing time** — needs a drug dictionary; high value, real ongoing cost. The extraction dictionary in `insights/note_intelligence.dart` is not one.
5. **Backend + sync drain** — the queue already exists and is populated.
6. **A small on-device language model** — the seam exists; see §1.11. Worth doing only once the deterministic features have been used in a real clinic and their gaps are known.
7. **Paediatric BMI centiles** — the BMI explanation currently declines to categorise a child's BMI, which is correct but unhelpful.
