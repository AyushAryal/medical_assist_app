# AI Architecture

How intelligence works in this app, end to end: the model layer, how context is
gathered and redacted, how prompts are formed, how output is grounded and shown,
and the two pipelines the app runs — the **assistant/query pipeline** and the
**generation pipeline** — plus the removable **agentic** layer.

Read this once and the rest of the AI code should be navigable.

---

## 0. The five rules everything obeys

Every AI path in the app is built on the same contract. If you remember only
this section, you can predict how any feature behaves.

1. **Deterministic engines are the product; a model only ever *adds*.** NEWS2,
   the query grammars, `NoteIntelligence`, the OCR geometry — these are the
   features. A model reworps text or widens the wording understood. Remove the
   model and everything still works, just less fluently.
2. **The model translates or rewrites; it never authors data.** It is handed
   the app's *own structured text* and asked to reshape it, or handed a
   question and asked to map it onto a *known* query. It cannot produce a value,
   a diagnosis, a filter, or a database write.
3. **On-device, or it does not run.** Every engine reports `runsOnDevice`. The
   image and text never leave the phone. There is no cloud call.
4. **A hallucination fails loudly, it never leaks into data.** In the query
   path a bad rewrite fails to parse and falls through to the clarifier. In the
   generation path a failed call falls back to the deterministic input. There is
   no path from model output to a stored record.
5. **Everything explains itself and stops at a proposal.** Redaction happens
   before any model sees text; authorisation happens before anything executes;
   mutations stop at a confirmation step; every answer carries a provenance
   trail or a grounded "Sources" list; generated content is badged.

---

## 1. The model layer

### 1.1 The one interface

`lib/data/services/assist/language_model.dart` — `LanguageModelEngine`. This is
the seam every model plugs into. It is small and deliberately shaped so the
model can only rewrite:

- `plainLanguageInstructions(plan)` — plan → patient instructions
- `spokenHandoff(structured)` / `spokenBrief(structured)` — reword a built
  handoff / pre-read
- `patientReminder(facts)`, `triageTalkingPoints(presentation)`,
  `referralLetter(record)`, `explainPlainly(data)`, `caseloadReport(figures)`
- `assignSentencesToSections(numberedSentences)` — classify note sentences into
  SOAP (returns *section names + indices*, not rewritten text)
- `rephraseAsKnownQuestion(request, vocabulary)` — map a question onto a known
  form (returns *a sentence*, re-parsed by the grammars)
- `extractValues(description, fields)` — read spoken measurements into JSON,
  each value then validated against field bounds

Note the shape: none of these returns a decision, a query, or a stored value.
The "authorship" tasks (`assignSentencesToSections`, `rephraseAsKnownQuestion`,
`extractValues`) return *classifications or sentences* that coded logic then
validates — so the model's output is checked, not trusted.

Generated text comes back as `LanguageModelDraft { text, engineName, sections }`
— permanently marked as generated, carrying the engine's name for the badge.

### 1.2 The implementations

| Engine | File | What it is |
|---|---|---|
| `LlamaEngine` | `data/services/assist/llama_engine.dart` | A downloaded GGUF model (Qwen/SmolLM/etc.) run through `llama.cpp` in a **background isolate**. `isReady()` = model file exists; a sticky `_failed` flag after a bad load. |
| `AppleFoundationLanguageModel` | `data/services/assist/apple_foundation_model.dart` | Apple Intelligence (Foundation Models) over the `app.medical/foundation_model` method channel. No download, uses the OS model. `isReady()` = availability query. |
| `ScriptedModel` | `test/helpers/scripted_model.dart` | Test double that answers with whatever it is told — so tests can force the bad cases. |

Each implementation owns its own prompts (they happen to match across engines);
the *caller* only picks a method.

### 1.3 Which engine is live — user-settable, graceful

`AiEnginePreference { auto, appleIntelligence, downloaded, off }`
(`data/services/assist/ai_engine_preference.dart`), persisted, chosen in
**Settings → AI assistant** (`AiSettingsScreen`).

`AppBootstrap.refreshAssistEngine()` resolves it:

```
auto              → Apple Intelligence if ready, else a downloaded model, else none
appleIntelligence → Apple Intelligence if ready, else none
downloaded        → a downloaded model if installed, else none
off               → none (deterministic features only)
```

`assistModelActive` (`_assistEngine != null`) gates every AI affordance in the
UI, so a feature's button only appears when a model can actually run it. Debug
builds auto-provision the smallest model unless the preference says otherwise.

---

## 2. Two pipelines

The app has **two** distinct AI flows. They share the model layer and the five
rules, but they solve different problems and live in different code.

```
  A. ASSISTANT / QUERY pipeline  (lib/ai/)        "ask about the register"
     question ─▶ preprocess ─▶ interpret ─▶ refine ─▶ authorise ─▶ execute ─▶ present

  B. GENERATION pipeline  (data/services/assist + features)   "reword this record"
     structured text ─▶ engine.method(prompt, text) ─▶ draft ─▶ badged, grounded, rendered
```

---

## 3. Pipeline A — the assistant / query pipeline (`lib/ai/`)

This is the "agent" that answers questions about the patient register
("patients on warfarin", "average BP by district", "highest BMI"). It is mostly
**deterministic grammars**; the model is one optional translator at the end.

`AssistPipeline` (`lib/ai/pipeline.dart`) is the single implementation shared by
the floating bubble and the full Ask page. Its stages:

```
  preprocess → interpret → (refine) → authorise → execute → present
```

### 3.1 Preprocess — normalise + redact  (`ai/preprocess.dart`)

- **Normalise**: lower-case, depunctuate, strip framing ("could you please show
  me…") so grammars match intent, not phrasing.
- **Redact**: pull identifiers *out of the text before anything downstream — and
  before any model — sees it*. This is rule 3/5 in action: the model that helps
  rephrase a question never receives a name or MRN.
- Colloquial phrasings are mapped onto a canonical question via
  `Paraphrases.canonical`, and the rewrite is recorded in provenance.

### 3.2 Interpret — the grammar chain, model last  (`ai/interpreter.dart`, `ai/interpreters/`)

An ordered `InterpreterChain`, most-specific first, each declining fast:

```
  PatientInterpreter   (a \pat smart-phrase names one person)
  OverviewInterpreter  (tiny fixed vocabulary)
  RankInterpreter      ("highest BMI"  — before analysis)
  AnalysisInterpreter  ("average bp by district")
  PatternInterpreter   (free-text cohort search — broadest net)
  ModelInterpreter     (only if a model is installed — LAST)
```

Each interpreter turns text into a typed `AssistIntent` (a `QueryIntent`,
`RankIntent`, `AnalysisIntent`, …) built against the closed clinical schema
(`ai/schema/` — eleven tables, a fixed field registry, a published question
vocabulary).

`ModelInterpreter` (`ai/interpreters/model_interpreter.dart`) is the *only* place
the model touches this pipeline, and its contract is one call:

> hand the model the redacted request **plus the published question bank**, get
> back **a sentence** (the nearest known question form), and **re-run that
> sentence through the very same grammars** as if the clinician had typed it.

Consequences, by design:

- **A hallucination fails loudly** — a rewrite naming a question the grammars
  don't answer simply fails to parse; the chain falls to the clarifier. There
  is *no path from model output to a query that didn't already exist.*
- **The audit trail stays readable** — provenance shows the wording that arrived
  and the question that ran; the clinician can disagree with the one thing the
  model did (the translation).
- **Capabilities stay honest** — the prompt is built from the same starters the
  in-app guide advertises, so the model can't be coaxed toward things the app
  doesn't do.

### 3.3 Refine — conversation context  (`ai/refinement/refiner.dart`, `ai/conversation.dart`)

A fragment that *changes the standing question* rather than starting a new one
("only the women", "per month instead", "what about visits") is folded into the
previous intent via `Refiner`, using the shared `AssistThread`. The thread lives
on the pipeline (not a widget) so the bubble and the full page are two windows
onto **one** dialogue; it is cleared on lock because a conversation about the
register is PHI.

### 3.4 Authorise — before anything executes  (`ai/authorisation.dart`)

`Authoriser.check(intent, request)` runs against `Entitlements` *before* any
handler runs. A disallowed intent returns a message, never data.

### 3.5 Execute — deterministic handlers  (`ai/handlers/`)

The typed intent is dispatched to a handler that queries through
`ClinicalRepository`: `QueryHandler`, `RankHandler`, `AnalysisHandler`,
`ReportHandler`, `OverviewHandler`, `PatientSummaryHandler`. All computation is
coded and offline; the model contributed *only* the wording back in 3.2.

### 3.6 Present + provenance  (`ai/presentation.dart`, `ai/provenance.dart`)

The handler returns a `Presentation` (a record list, a chart, a table, a message,
a change-awaiting-confirmation). Adding an output type is adding a
`Presentation` + handler case, not a new widget path.

Every answer carries a `Provenance` trail — the stage-by-stage record (reword →
interpret → context → authorise → execute → present), shown behind the info
control. `isGenerated` (did a model contribute anything?) drives the AI badge,
and *only* that: a purely deterministic answer is **not** badged, so the badge
keeps its meaning.

---

## 4. Pipeline B — the generation pipeline (rewrite the record)

This is the path behind Brief, Handoff read-aloud, Referral, Explain, Daily
brief, patient instructions, recall reminders and triage talking points.

### 4.1 Context retrieval — deterministic assembly, never the raw record

The model is **never** handed the database. It is handed a **structured text
block the app built deterministically**:

- **`RecordSummary.plainText`** (`clinical/summary/`) — the pre-read: allergies,
  problems, meds, latest obs, last-seen, each with its own source, "not
  recorded" as a value. Built by `SummaryBuilder` from a `ChartSnapshot`
  projection assembled in `data/summary/chart_summary.dart`.
- **`Handoff.plainText`** — the deterministic SBAR (`HandoffBuilder`), reusing
  the record summary for Background.
- **Dashboard figures** for the caseload brief; the presenting complaint for
  triage prompts; the recall facts for a reminder.

So "context retrieval" here is **deterministic composition**, not vector search:
the app decides exactly what the model may see, which is why the output can be
grounded (§4.4) without the model inventing citations.

### 4.2 Prompt — fixed per task, model-agnostic

Each engine method carries a **fixed instruction** ("Rewrite this SBAR handoff
as one short paragraph… keep every fact, add none, 'not recorded' stays 'not
recorded'"). The prompt is `instruction + "\n\n" + structuredText`. The same
instructions exist in both `LlamaEngine` and `AppleFoundationLanguageModel`, so
**swapping the engine does not change the behaviour** — the feature is defined
by the prompt + the structured input, not the model.

### 4.3 Invocation + failure — `AiDraftSheet`

`features/assist/widgets/ai_draft_sheet.dart` is the shared envelope. Given a
`generate: (engine) => engine.someMethod(text)` closure, it:

1. resolves the engine (rebuilds it if a fresh download reads "not ready"),
2. shows a shimmer while generating,
3. renders the result via `MarkdownView` (tables/headings survive),
4. on any failure the engine method returns the **structured input unchanged**
   (a deterministic handoff *is* a valid handoff), so there is no dead end.

The caller owns the *task*; the sheet owns the *safety envelope*, so no feature
re-implements badging, grounding, or degradation.

### 4.4 Output context — badged, grounded, rendered

- **Badged**: `AiBadge` + a per-feature `notice` mark it as generated, "read it
  before you rely on it".
- **Grounded**: an optional `List<AiSource>` powers a **"Sources (N)"** button
  showing the *exact record lines fed to the model*. Because those come from the
  app's own data (not the model), they cannot be hallucinated citations.
  `AiSource.onOpen` is the hook for a source to open its origin (a record
  section, an attached PDF).
- **Rendered**: `MarkdownView` (`core/widgets/`) renders pipe tables, headings
  and rules, so generated structure shows properly; the underlying text stays
  plain and copyable.

---

## 5. The agentic layer (removable) — filling forms by voice

Separate from both pipelines is the **agentic module**, the "operate a screen's
fields" capability. It is designed to be *deleted* without touching the app.

### 5.1 The seam  (`core/agentic/`)

- `AgentSurface` / `AgentField` — a screen publishes its operable fields: id,
  label, kind (integer/decimal/pair/text), unit, example, aliases, **min/max**.
- `AgentHost` — the driver interface. `AgentScope` / `AgentSlot` render an
  affordance *or nothing* when no host is installed (`AgentScope.of() == null`).

The composition root (`main.dart`) is the only place that installs a host, so
removing `lib/agentic/` and that one line leaves every `AgentSlot` empty and the
app fully working. A `removability_test` enforces the one-way dependency.

### 5.2 The driver — propose-and-confirm  (`lib/agentic/`)

The guided-dictation driver turns speech into field values, and **nothing
writes to the form until the clinician confirms**:

- `SpokenValueParser` — parses an utterance into a `NumberUtterance` /
  `PairUtterance` / `CommandUtterance` / `UnclearUtterance`; **declines
  ambiguity** rather than guessing.
- `ContinuousDictationController` — routes each value to a field by alias,
  *stages* it (nothing commits until `commit()`), and cleans transcripts.
- `SurfaceExtraction` — validates model output against the field bounds
  (`AgentField.min/max`); an out-of-range or unknown field is discarded.
- `extractValues` (the model method) is used only to parse harder phrasings; its
  JSON is validated the same way. The deterministic parser works without it.

This is the same principle as the rest of the app expressed as a widget system:
the model proposes, the bounds sanitise, the clinician confirms, one audited
write path stores it.

---

## 6. Vision / OCR as a capability (not image "understanding")

`TextScanner` (`data/services/ocr/`) is a capability seam like the language
model: **Apple Vision natively on iOS** (`VNRecognizeTextRequest`), **ML Kit**
elsewhere, chosen by `TextScanner.platformDefault()`.

Honest scope, stated deliberately:

- **Text + geometry, on-device.** It returns each line with its box.
- **Structure is reconstructed deterministically** (`table_reconstruction.dart`):
  aligned multi-column runs → Markdown tables; taller lines → headings; large
  vertical gaps → section breaks. Prose by default; a table only when earned.
- **No image *interpretation*.** Apple Intelligence is text-only (can't take an
  image); Vision classification is generic scene labels, not medical meaning;
  Vision gives no font weight, so **bold/italic and arbitrary alignment are
  never inferred**. Guessing format would be hallucinating it.

The result flows into the working notes as Markdown, rendered on demand by the
preview toggle — same `MarkdownView` as generated output.

---

## 7. Where the safety boundaries actually sit

Putting the two pipelines together, every place the model could cause harm has a
coded gate in front of it:

```
  QUERY PIPELINE
    redact ────────────▶ (model never sees identifiers)
    grammars re-parse ──▶ (model output that doesn't parse = no query)
    authorise ─────────▶ (before any handler runs)
    provenance ────────▶ (every stage recorded; badge only if a model helped)

  GENERATION PIPELINE
    structured input ──▶ (model never sees the raw record)
    fixed prompt ──────▶ (behaviour independent of the engine)
    fallback to input ─▶ (failure degrades, never dead-ends)
    badge + Sources ───▶ (marked generated; grounded in real inputs)

  AGENTIC
    bounds validation ─▶ (out-of-range values discarded)
    stage + confirm ───▶ (nothing writes itself)
    ClinicalRepository ▶ (single audited write path)
```

Nothing in the app writes a clinical value from a model. Every model output is
either re-validated by coded logic (a re-parsed question, a bounded value, a
classified sentence) or shown as a marked draft for a human to accept.

---

## 8. File map (where to look)

| Concern | Files |
|---|---|
| Model interface + draft | `data/services/assist/language_model.dart` |
| Engines | `…/llama_engine.dart`, `…/apple_foundation_model.dart`, `ios/Runner/AppDelegate.swift` (native channels) |
| Engine selection | `data/services/assist/ai_engine_preference.dart`, `core/app_bootstrap.dart` (`refreshAssistEngine`) |
| Assistant/query pipeline | `lib/ai/pipeline.dart` + `ai/{preprocess,interpreter,intent,authorisation,refinement,presentation,provenance}.dart`, `ai/interpreters/`, `ai/handlers/`, `ai/schema/` |
| Generation UI | `features/assist/widgets/ai_draft_sheet.dart` (+ `AiSource`), `core/widgets/markdown_view.dart` |
| Structured inputs | `clinical/summary/`, `data/summary/chart_summary.dart` |
| Agentic | `core/agentic/`, `lib/agentic/`, `agentic/drivers/` |
| OCR | `data/services/ocr/`, `ios/Runner/AppDelegate.swift` |
| Settings | `features/settings/ai_settings_screen.dart` |

---

## 9. Adding a new AI feature — the checklist

1. Decide the task is **rewrite/extract/translate**, never authorship.
2. Build the **structured input deterministically** (a summary, a projection) —
   never pass the raw record.
3. Add a **fixed-prompt method** to `LanguageModelEngine` and implement it in
   both engines + the `ScriptedModel`.
4. Invoke through **`AiDraftSheet`** (badge, Markdown, failure-fallback for
   free); pass **`sources`** for grounding.
5. Gate the entry point on **`assistModelActive`**, and make sure the feature
   still does something useful with **no model**.
6. If it interprets a question about data, it belongs in **Pipeline A** as an
   interpreter/handler, not here.
