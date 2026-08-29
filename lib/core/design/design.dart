/// The single entry point for everything visual.
///
/// **Rule: feature code imports this file and nothing else from the design
/// layer.** No screen defines its own `BoxDecoration`, picks its own colour,
/// or invents a new card shape. If a screen needs something this file does not
/// export, the component is added *here* first — that is what keeps the app
/// looking like one product instead of fifteen.
///
/// The committed concept is documented in `DesignSystem.md`. It is
/// deliberately narrow: translucent layered surfaces, one accent, clinical
/// severity colour reserved for clinical meaning, minimal gradients. Do not
/// introduce a second visual language alongside it.
///
/// Enforced by `test/core/design_guardrails_test.dart`, which fails the build
/// on hardcoded colours, raw radii and ad-hoc surface containers in
/// `lib/features/`.
library;

// Tokens — colours, spacing, radii, typography. Always via context extensions.
export '../theme/theme_config.dart'
    show ClinicalPalette, ClinicalPaletteX, ThemeMetrics, ThemeTypography;
export '../theme/theme_scope.dart';

// Surfaces — the only approved containers for content.
export '../widgets/glass.dart'
    show GlassPanel, GlassChrome, AmbientBackground, StatusBarScrim;
export '../widgets/section_card.dart' show SectionCard;
export '../widgets/sheet_scaffold.dart' show SheetScaffold;
export '../widgets/confirm_dialog.dart' show confirmDialog;

// Layout and responsive behaviour.
export 'layout.dart';
export 'adaptive.dart';

// Motion for generated content and in-progress inference. A bounded exception
// to the minimal-gradients rule — see DesignSystem.md §6.
export 'ai_effects.dart'
    show
        AiGlowBorder,
        AiShimmer,
        AiTextPlaceholder,
        AiBadge,
        AiSparkleIcon,
        AiAuroraBackground,
        GlowLasso,
        GeneratedText,
        GeneratedTextLegend,
        GeneratedSpanController,
        generatedHighlightColor,
        buildGeneratedSpans;
export 'ai_waveform.dart' show SiriWaveform;
export 'playback_waveform.dart' show PlaybackWaveform;

// Controls and inputs.
export '../widgets/quick_fields.dart'
    show LabeledField, NumericField, ChoiceChipRow;
export '../widgets/quick_action.dart' show QuickAction;
export '../widgets/contact_actions.dart'
    show CallButton, ContactRow, ContactActions;

// Status and identity.
export '../widgets/status_pill.dart' show StatusPill, PillTone;
export '../widgets/patient_avatar.dart' show PatientAvatar, AvatarBadge;
export '../widgets/patient_header.dart' show PatientIdentityBar, AllergyBanner;

// Data display.
export '../widgets/vital_value.dart' show VitalValue;
export '../widgets/sparkline.dart' show Sparkline, MiniBarChart;
export '../widgets/data_chart.dart' show DataChart;
export '../widgets/empty_state.dart' show EmptyState;

// Explaining derived values. Anything the app worked out for itself carries an
// InfoDot; the rule is documented in `clinical/explanations.dart`.
export '../widgets/info_dot.dart'
    show InfoDot, ExplainSheet, ExplainedLabel;
export '../../clinical/explanations.dart'
    show MetricExplanation, ExplainRow, ExplainConfidence, ExplainConfidenceX;

// Composite patterns — prefer these over hand-assembling rows.
export 'patterns.dart';
