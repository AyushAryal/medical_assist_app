/// NEWS2 — the Royal College of Physicians' National Early Warning Score 2.
///
/// The implementation now lives in the shared kit (`opt_kit/clinical.dart`),
/// where it was ported **verbatim from this file** so all three medical apps
/// score from one safety-critical source. This file is a thin re-export that
/// keeps the app's local names (`News2Calculator`, `News2Input`, …) so call
/// sites and the app's own boundary tests are unchanged — those tests are the
/// proof that the kit copy behaves identically.
///
/// Scope and safety, verbatim from the standard's own guidance:
///
/// * Validated for **acutely ill adults aged 16 and over**.
/// * **Not** validated in pregnancy, and **not** for children — both have
///   physiology that makes the adult bands misleading. `News2Calculator`
///   refuses to score those patients rather than returning a number the UI
///   might display.
/// * It is a **track-and-trigger aid**, not a diagnosis. Escalation is always
///   a clinical decision; the score never overrides concern about a patient
///   who looks unwell.
///
/// SpO2 Scale 2 (target 88–92% in chronic hypercapnic respiratory failure)
/// must be prescribed by a clinician per patient, so it is opt-in via
/// `News2Input.useSpo2Scale2`.
library;

export 'package:opt_kit/clinical.dart'
    show
        Consciousness,
        ConsciousnessX,
        News2Risk,
        News2RiskX,
        News2Input,
        News2Unavailable,
        News2Result,
        News2Calculator;
