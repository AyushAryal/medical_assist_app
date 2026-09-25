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
export '../widgets/markdown_view.dart' show MarkdownView;
export '../widgets/sheet_scaffold.dart' show SheetScaffold;
export '../widgets/confirm_dialog.dart' show confirmDialog;
export '../widgets/draft_banner.dart' show DraftRestoredRow;

// Layout and responsive behaviour.
export '../theme/app_theme.dart' show kPillNavBarHeight, pillNavBottomMargin;
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
        AiPillButton,
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
export '../widgets/capsule_action.dart' show CapsuleAction;
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
export '../widgets/loading_state.dart' show LoadingState;
export '../widgets/skeleton_list.dart' show SkeletonList;

// Explaining derived values. Anything the app worked out for itself carries an
// InfoDot; the rule is documented in `clinical/explanations.dart`.
export '../widgets/info_dot.dart' show InfoDot, ExplainSheet, ExplainedLabel;
export '../../clinical/explanations.dart'
    show MetricExplanation, ExplainRow, ExplainConfidence, ExplainConfidenceX;

// Composite patterns — prefer these over hand-assembling rows.
export 'patterns.dart';

// Canonical primitives from the shared OptERP kit. Kit widgets read
// `Theme.of(context).colorScheme`, which `AppTheme.build` populates from this
// app's JSON tokens — so they stay tokenized and carry no colour literals into
// feature code. The glass surface language (SectionCard/GlassPanel) remains
// this app's own; these are the family-shared data primitives only.
export 'package:opt_kit/opt_kit.dart'
    show
        OptDetailRow,
        OptStatCard,
        // Canonical transient feedback — one voice for toasts across the
        // family, with typed durations (success/info 2400ms, error 4000ms).
        OptToast,
        OptToastType,
        // Canonical confirmation dialog. `confirmDialog` above remains the
        // app-local name and delegates to this.
        showOptConfirmDialog,
        // The family motion scale — transitional durations come from here,
        // not from per-screen literals.
        OptMotion,
        // The family-standard floating tab bar. Its selection blob reads the
        // BrandTheme extension AppTheme.build derives from this app's
        // `heroGradient` palette token, so it stays tokenized end to end.
        PillNavBar,
        PillNavItem,
        // The family-canonical Settings page shape and About brand moment.
        OptSettingsScaffold,
        OptSettingsSection,
        OptAboutPage,
        // The family-canonical patient identity header every health app's
        // patient page opens with. Chip colours come from this app's own
        // clinical palette — clinical severity stays OptDAI's meaning.
        OptPatientHeader,
        PatientHeaderChip,
        // The family-canonical "last note" surface — the latest signed note as
        // a first-class, zero-navigation chart artifact (chart-biopsy: the
        // median chart review reads exactly one prior note).
        OptLastNoteCard,
        // Header-with-chevron container for demoted, on-request content
        // (trend grids, historical tables). Collapsed means zero body height.
        OptCollapsibleSection,
        // Interruption-safe form drafts. `DraftGroup` binds a form's text
        // controllers to one snapshot record; the backing store is the
        // encrypted database, installed at unlock via `OptDrafts.store`
        // (see core/db/draft_store.dart). Pair a restore with the app's
        // `DraftRestoredRow` above.
        DraftGroup,
        OptDrafts;

// The SBAR-shaped 30-second cross-cover card — the glanceable top of the
// handoff sheet. Its risk chip reads the kit NEWS2 types this app already
// re-exports through `clinical/news2.dart`, tinted by the app's own clinical
// severity tokens via Theme.colorScheme.
export 'package:opt_kit/clinical.dart' show OptSituationCard;

// Research-backed trend charts from the kit: overview-first small multiples
// (OptTrendGrid) with details-on-demand (OptTrendDetail). The app's gap-aware
// Sparkline above stays the tool for series with missing observations — the
// kit model has no null-gap concept.
export 'package:opt_kit/charts.dart'
    show
        TrendSeries,
        TrendPoint,
        OptSparkline,
        OptTrendGrid,
        OptTrendDetail,
        TrendRange;
