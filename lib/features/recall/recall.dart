/// The recall list: an optional, clinic-configurable workflow module.
///
/// Public surface only. Gated by [RecallModule.isVisible]; when the gate is
/// closed nothing renders, and the folder can be lifted out without touching
/// another feature.
library;

export 'recall_board_screen.dart' show RecallBoardScreen;
export 'recall_module.dart' show RecallModule;
export 'widgets/recall_card.dart' show RecallCard;
