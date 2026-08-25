# Clinical Records

An offline-first Flutter application for recording patient encounters, vital
signs and clinical notes. Everything is stored in an encrypted SQLite database
on the device; there is no backend and none is contacted.

Dictation is transcribed by Whisper running on the device. The only network
request the app can make is downloading that speech model, on an explicit tap.
Two offline provisioning routes exist so the `INTERNET` permission can be
deleted outright — see [Features.md §3b](Features.md).

## Documentation

| File | Contents |
|---|---|
| [SystemArchitecture.md](SystemArchitecture.md) | Layering, security model, lock lifecycle, decision support, theming, safety properties |
| [SystemSchema.md](SystemSchema.md) | Database schema, column-by-column, with the reasoning behind each convention |
| [Features.md](Features.md) | What is built, what is scaffolded, what is planned |

## Running

```bash
flutter pub get
flutter run                  # attached device
flutter test                 # unit tests, all offline
flutter analyze              # clean
./tool/install.sh            # release build + install on an attached phone
```

`tool/install.sh` builds arm64 only. The speech-recognition runtime carries
~24 MB of native library *per ABI*, and building all four roughly doubles the
APK for no benefit on a device you are holding.

```bash
./tool/fetch_speech_model.sh --push   # provision the speech model, no root
```

Fetches Whisper tiny.en (~104 MB) and pushes it into the app's own external
files directory, which needs neither root nor a runtime permission on either
side. The app finds it on launch; Settings › Dictation removes it. See
[Features.md §3b](Features.md).

First launch asks for a 6-digit PIN and seeds a clinic named "My clinic".
Biometric unlock is opt-in from Settings once a PIN exists.

**Requirements**: Flutter 3.44+, Android minSdk 24, iOS 13+.

## Shape of the code

```
lib/
├── clinical/     pure clinical logic — NEWS2, age-banded reference ranges,
│                 bedside calculations, and the explanation each one carries.
│                 No Flutter imports, fully unit-tested.
│   └── insights/ deterministic on-device analysis: duplicate detection,
│                 deterioration trends, note term extraction, schedule
│                 estimates. No model, no inference.
├── core/         database, security, theming, routing, audit, modules
├── data/         models, DAOs, services, and the single write path
│   └── services/ audio capture and voice activity detection, on-device
│                 transcription, and the assist facade
└── features/     one directory per screen area
```

Four rules hold throughout:

1. **Screens never touch a DAO.** Every mutation goes through
   `ClinicalRepository`, which is what guarantees an audit entry, a sync-queue
   entry, and the invariants that make the record defensible.
2. **No widget hardcodes a colour or a spacing value.** Appearance comes from
   `assets/theme/clinical.json` via `context.palette` / `context.metrics`.
3. **Anything the app worked out for itself explains itself.** Every derived
   number carries an `InfoDot` showing the method, the inputs, and what it
   cannot be trusted to say. See [DesignSystem.md §4b](DesignSystem.md).
4. **Nothing writes to a record on the app's own initiative.** Templates,
   dictation transcripts, duplicate warnings and extracted terms all propose;
   a clinician disposes. Every one of them is one tap to accept and one to
   dismiss.

## A note on the analysis features

The features under [Features.md §1.10](Features.md) are deterministic — string
similarity, robust line fitting, dictionary matching, medians. That is a
deliberate choice rather than a limitation waiting to be lifted. They run
instantly on any device, behave identically everywhere, and can be explained to
the clinician being asked to act on them, which is the property that decides
whether decision support gets used or ignored.

Two of them carry constraints that are part of the feature:

- **Duplicate detection never blocks registration.** A check that can refuse
  gets defeated within a week, usually by misspelling a name on purpose.
- **The attendance estimate exists to offer support, never to withhold it.** It
  uses only a patient's own appointment history — no age, sex or address.

The same principle governs the **Ask** screen, which answers questions about the
register: no SQL is ever generated from what is typed. A phrase is matched onto
filters a human wrote, every answer shows those filters in clinical English, and
an unrecognised question says so rather than answering a different one. A wrong
recall list is read by nobody — that is the point of running it — so a list that
quietly misses three patients looks exactly like a correct one.

`LanguageModelEngine` defines a seam for a small on-device model and ships no
implementation. If one is added, it chooses among safe queries; it does not
write them.

## A note on scope

The clinical decision support in this app — NEWS2 scoring and reference-range
flagging — is **decision support only**. It is not a diagnosis, it defers to
local escalation policy, and it never overrides the clinician in front of the
patient. `News2Calculator` refuses to score patients outside its validated scope
(under 16, pregnant, or with incomplete observations) rather than return a
number the UI might display.

One requirement from the original brief was deliberately not implemented as
written — gating *read access to existing patient records* behind a
subscription. The reasoning is in [Features.md §3](Features.md).
