/// Motion for the moments the app is working something out.
///
/// This is a deliberate, bounded exception to the system's "minimal gradients"
/// rule, and it is worth being explicit about why it earns one. Everywhere
/// else, a gradient would be decoration. Here it is a *signal*: it marks the
/// difference between text the clinician wrote and text a machine produced, and
/// between a screen that is idle and one that is thinking. Those are exactly
/// the distinctions this app must never let blur.
///
/// The rules that keep it from spreading:
///
/// * **Only for generated content and in-progress inference.** Never for a
///   save, a load, or anything a clinician did themselves.
/// * **Colour comes from the palette.** No new hues; the sweep is built from
///   `accent`, `primary` and `info`, so it re-skins with everything else.
/// * **It stops.** Every animation here is bounded by an `active` flag and
///   disposes its controller. Nothing loops forever behind a finished result.
/// * **It respects reduced motion.** When the platform asks for less motion
///   the effect degrades to a static tint rather than being merely slowed —
///   for a vestibular-sensitive user a slow sweep is worse than none.
///
/// Documented as a known deviation in `DesignSystem.md` §6.
///
/// This is the barrel for the `ai_effects/` capability: each effect lives in
/// its own focused file, and this file re-exports the public surface. The
/// shared motion helpers in `ai_effects/effects_motion.dart` are intentionally
/// not re-exported — they stay internal to the design layer.
library;

export 'ai_effects/ai_glow_border.dart';
export 'ai_effects/ai_shimmer.dart';
export 'ai_effects/ai_text_placeholder.dart';
export 'ai_effects/ai_badge.dart';
export 'ai_effects/ai_aurora.dart';
export 'ai_effects/ai_sparkle.dart';
export 'ai_effects/generated_text.dart';
export 'ai_effects/generated_span_controller.dart';
export 'ai_effects/glow_lasso.dart';
export 'ai_effects/gradient_box_border.dart';
