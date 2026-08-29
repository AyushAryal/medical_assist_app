/// The triage board: an optional, clinic-configurable workflow module.
///
/// Public surface for the rest of the app. Nothing outside this folder reaches
/// past this barrel. The module is gated by [TriageModule.isVisible]; when the
/// gate is closed — unlicensed or switched off — none of this renders, and the
/// whole folder can be deleted without touching another feature.
library;

export 'triage_board_screen.dart' show TriageBoardScreen;
export 'triage_module.dart' show TriageModule;
export 'widgets/triage_card.dart' show TriageCard;
