# Design System — "Clinical Material"

**One concept, committed.** This document exists so that design decisions are
made *once* here, not re-invented on every screen. If a screen needs something
this system does not provide, the component is added to
[`lib/core/design/`](lib/core/design/) first.

Enforced by [`test/core/design_guardrails_test.dart`](test/core/design_guardrails_test.dart),
which fails the build on hardcoded colours, literal radii, and ad-hoc card
surfaces inside `lib/features/`.

---

## 1. The concept

A clinical record app that is calm and legible **without being lifeless**.
Restraint applies to *decoration*, not to craft.

| Principle | What it means in practice |
|---|---|
| **Layered materials, not flat panels** | Content sits on translucent, blurred surfaces. Depth comes from layering and blur, not from drop shadows or outlines. |
| **Minimal gradients** | Gradients are not used for surfaces, buttons or charts. The only exception is the ambient background wash, which is a barely-perceptible two-hue field that exists solely so translucent panels have something to reveal. |
| **Colour carries meaning** | The severity palette (`normal` / `caution` / `critical`) is reserved for clinical state. `accent` is the one non-semantic highlight. A red delete button and an unstable patient must never look alike. |
| **Generous type hierarchy** | Large, tight-tracked titles against quiet body text. Numeric clinical values use tabular figures so columns align. |
| **Hairline separators** | 0.5px, not 1px. A full logical pixel reads as a heavy rule on a modern display. |
| **Never colour alone** | Every abnormal value also carries a text marker (`H`, `L`, `HH`, `LL`). Correct for colour-blind users and in direct sunlight. |

---

## 2. The surface stack

Three levels, and only three:

```
  ambient wash        AmbientBackground   — app root, behind everything
      ↓
  ground              scaffold            — transparent; shows the wash
      ↓
  material panel      GlassPanel          — translucent + blurred content
      ↓
  chrome              GlassChrome         — app bars, nav; more opaque
```

`GlassPanel` is the **only** approved content container. `SectionCard` wraps it
with a title/subtitle/leading/trailing header and is what screens normally use.

Blur is expensive. Panels and chrome only — **never per row in a long list**.

---

## 3. Tokens

Everything visual comes from [`assets/theme/clinical.json`](assets/theme/clinical.json).
No widget hardcodes a colour, radius or spacing value.

Access through context extensions:

```dart
context.palette      // ClinicalPalette — colours
context.metrics      // ThemeMetrics — spacing, radii, blur, opacity
context.texts        // TextTheme
context.glassOpacity // brightness-matched panel opacity
context.iconTintAlpha// brightness-matched icon tint
context.isDark
```

### Spacing and radii

| Token | Use |
|---|---|
| `spaceXs` … `space2xl` | All padding and gaps. Prefer `Gap.md()` / `HGap.sm()` over literal `SizedBox`. |
| `radiusXs` | Progress tracks, accent strips, tiny badges |
| `radiusSm` | Buttons, inputs, small tiles |
| `radiusMd` | Panels and cards |
| `radiusLg` | Sheets, pills |

### Brightness rules

Two mistakes this system explicitly guards against, both learned the hard way:

1. **Surface elevation must not invert between modes.** In light mode the
   ground is tinted and cards are white; in dark mode the ground is near-black
   and cards are *lighter*. Getting this backwards makes every screen look
   flat, and it is invisible until you view it on a dark device.
2. **Tint alpha is not shared across modes.** The same alpha that reads as a
   confident tint on white is invisible on black. Hence
   `iconTintAlphaLight` / `iconTintAlphaDark` as separate tokens.

---

## 4. Component catalogue

Import **one** file:

```dart
import '../../core/design/design.dart';
```

| Component | Use for |
|---|---|
| `GlassPanel` | Raw translucent surface |
| `SectionCard` | Titled content block — the default |
| `HeroPanel` | The single most important thing on a screen |
| `Callout` | A whole section that needs to read as urgent |
| `ContentWidth` | Caps body width on tablets |
| `Gap` / `HGap` | Standard spacing |
| `PersonRow` | Any person in any list — one implementation, always |
| `DetailRow` | Label/value line inside a panel |
| `MetricChip` | A count that is context, not an action |
| `StatusPill` | Short status label; tone from the severity palette |
| `QuickAction` | Dashboard action tile |
| `PatientAvatar` | Initials on a stable per-record colour |
| `PatientIdentityBar` | Pinned identity strip |
| `AllergyBanner` | Three-state allergy banner |
| `VitalValue` | An observation with its reference flag |
| `Sparkline` / `MiniBarChart` | Small inline trend and count charts |
| `DataChart` | Every analytical chart: bar, column, line, area, pie, donut, scatter, histogram |
| `EmptyState` | Says what to do next, not just that it's empty |
| `LabeledField` / `NumericField` / `ChoiceChipRow` | Inputs |
| `CallButton` / `ContactRow` | Phone and SMS |
| `InfoDot` / `ExplainSheet` | **Required** beside anything the app worked out for itself |
| `TwoPane` / `DetailPanePlaceholder` | Master–detail on a wide screen |
| `SplitColumns` | Two editorial columns, order chosen by the caller |
| `AdaptiveColumns` | Flow of interchangeable cards into as many columns as fit |
| `AiGlowBorder` | A surface that is thinking |
| `AiShimmer` / `AiTextPlaceholder` | Text being produced |
| `AiBadge` | **Required** on generated content until the clinician edits it |
| `AiSparkleIcon` | A control that starts an AI action |
| `AiAuroraBackground` | A drifting colour field behind an AI surface |
| `SiriWaveform` | Live voice input, driven by the real microphone level |

---

### Why the charts are hand-drawn

`DataChart` is one widget over eight shapes, and none of it comes from a
charting package. Three reasons, in order of how much they matter:

1. An offline clinical app should not take a dependency it cannot audit for
   where it sends telemetry.
2. The app's palette, radii and type scale are the whole visual language, and
   charting libraries bring their own.
3. Every chart here has a caveat to honour — a gap that must stay a gap, a
   folded "Other" slice, a part-finished final bar, an average that is unknown
   rather than zero — and a general-purpose library has no way to express those.

The *choice* of shape is made upstream from the shape of the data, not by the
caller, so it arrives with the data. See Features §1.10bb.

Three rules the painters hold:

- **Colour never carries clinical meaning here.** The chart palette is the
  accent plus the avatar tones; the severity colours are excluded. Red in this
  app means a patient is unwell, and a red slice meaning "appointments in Ward
  3" would make that vocabulary unreliable everywhere it actually matters.
- **A smoothed line never overshoots its own data.** Control points are kept
  short, so the curve cannot bulge above the highest point or below the lowest.
  A line that looks better than the data is a chart that lies for looks.
- **A track is not a bar.** The faint slot behind each bar stays far lighter
  than any real value — a solid track makes an empty week read as a full one,
  which is worse than drawing nothing.

Motion is bounded: the series draws itself in once over 720 ms and stops. A
chart that pulses forever competes with the data on it. The same rule governs
the composer's glow on the Ask page, which lights on focus and while dictation
is live, and is inert otherwise — a control that shimmers permanently stops
meaning anything, and on a clinical screen it reads as an alert.

---

## 4b. Two rules that are not about appearance

### Every derived number carries its derivation

An early warning score, a reference-range flag, a trend arrow, a wait estimate
and a duplicate warning are all assertions the app makes on the clinician's
behalf. A number with no visible derivation is either believed uncritically or
ignored entirely, and both are worse than showing the working — so **anything
computed gets an `InfoDot`**.

The explanation is built by `clinical/metric_explanations.dart` or by the
calculator that owns the rule, never in the widget, so that a threshold and its
account of itself change together. An explanation that has drifted from the code
is worse than none: it is a confident lie.

`MetricExplanation` carries four things, and the last two are the ones people
skip:

| Field | Why it is there |
|---|---|
| `method` | Steps a reader could reproduce with a calculator |
| `derivation` | The inputs for *this* record, not a generic example |
| `confidence` | `validated` / `measured` / `heuristic` / `insufficientData`. A rule this app invented must never be mistaken for a published instrument |
| `caveat` | What a reader would otherwise get wrong. Absence from a warning list is not reassurance, and every heuristic says so |

### Layout responds to width, not to device

`Breakpoint.compact` / `medium` / `expanded`, via `context.breakpoint`. Never
"is this a tablet" — a phone in landscape, a small tablet in portrait and a
split-screen window all want different layouts and all answer that question the
same way. Guarded by `design_guardrails_test.dart`.

`ContentWidth` caps a *measure* for running text. It is the wrong tool for a
screen made of panels: applying a 780px cap to a landscape tablet is what
produces a narrow strip between two empty margins. Panel-based screens use
`ContentWidth.columns` and lay out with `SplitColumns`.

`SplitColumns` takes `primary` and `secondary` explicitly and does **not**
rebalance by height. On a clinical chart, which panel the eye lands on first is
a safety property; allergies must not migrate to the bottom of a second column
because the columns balanced better that way. Use `AdaptiveColumns` only where
order genuinely does not matter.

---

## 4c. Hierarchy on a screen that explains itself

A screen that teaches its own vocabulary accumulates explanatory panels, and
they are the easiest thing in the system to get wrong: three near-identical
cards is how a screen stops having a hierarchy — everything looks equally
important, so nothing reads as important.

The rule: **teaching material must not use the content surface.** `GlassPanel`
and `SectionCard` mean "this is a result". A hint, a guide or an example uses a
tinted, outlined strip instead, sits above the content, and folds away once the
user starts working. Say a thing once, in one place.

---

## 5. Rules for adding

1. **Add to `lib/core/design/`, then use it.** Never define a visual component
   inside a feature directory.
2. **No new colours.** If a component needs a colour, it takes one from the
   palette. If the palette lacks it, add a token to the JSON.
3. **No second visual language.** Do not introduce a Material-default card, an
   outlined variant, or a new elevation scheme alongside the glass stack.
4. **Charts follow the data-viz rule**: an empty value must not read as a full
   one. Tracks stay far lighter than any real bar.
5. **Colour is never the only signal.**
6. **Anything derived carries an `InfoDot`.** See §4b.
7. **Ask `context.breakpoint`, never `context.isTablet`.**
8. **Guidance does not get a content surface.** See §4c.

---

## 6. Known deviations

| Where | Why |
|---|---|
| `ImageViewer` uses absolute black and white | A full-screen photo viewer should not tint clinical imagery with the app's palette. Colour accuracy matters more than brand consistency when the image is the diagnosis. |
| Icon tint alpha differs by brightness | Physically necessary — see §3. |
| `ai_effects.dart` and `ai_waveform.dart` use animated gradients | The one place a gradient is a *signal* rather than decoration. It marks the boundary between text a clinician wrote and text a machine produced, and between a screen that is idle and one that is thinking. In a record read years later by someone who was not there, that distinction is the difference between evidence and hearsay. Confined to five components, built from palette hues only, bounded by an `active` flag, and degrading to a static tint under reduced-motion — a slow sweep is worse than none for a vestibular-sensitive user. `design_guardrails_test.dart` fails the build on a gradient written anywhere in `lib/features/`. The severity hues (`caution`, `critical`) are deliberately excluded from every sweep — they mean a clinical state, and borrowing them for decoration would blunt the one signal that must never be ambiguous. |
| `SiriWaveform` follows the live microphone level | It would be easier to animate a pleasant loop regardless of input. The one job this display has is letting a clinician confirm the microphone is picking them up *before* they trust it with a consultation they will not repeat, and a decorative loop would destroy exactly that. |
