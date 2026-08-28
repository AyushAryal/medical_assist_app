import '../../core/agentic/agent_surface.dart';
import 'spoken_value.dart';

/// What one utterance did to the guided flow, so the UI can react and read it
/// back to the clinician.
enum GuidedOutcome {
  /// A value was proposed into the current field; awaiting confirm.
  proposed,

  /// Moved on to the next field (the previous value, if any, is kept).
  advanced,

  /// Left the current field empty and moved on.
  skipped,

  /// Cleared the current field; the clinician re-dictates it.
  redone,

  /// Stepped back to the previous field.
  wentBack,

  /// Nothing understood; the flow re-asks the same field.
  unclear,

  /// The flow finished; the clinician reviews and saves.
  completed,
}

/// A snapshot the UI renders: which field we are on and what was just proposed.
class GuidedState {
  const GuidedState({
    required this.field,
    required this.index,
    required this.total,
    required this.awaitingConfirm,
    required this.complete,
  });

  /// The field currently being dictated, or null once [complete].
  final AgentField? field;
  final int index;
  final int total;

  /// True when a value has been proposed for [field] and the flow is waiting
  /// for "next" (confirm and advance) or "redo".
  final bool awaitingConfirm;
  final bool complete;
}

/// The guided-dictation flow: walk a screen's [AgentSurface] one field at a
/// time, turning each spoken [Utterance] into a proposed value or a control
/// action. Deliberately propose-and-confirm — a value is set on the field but
/// the clinician still confirms ("next") and ultimately saves, so a misheard
/// number never lands silently.
///
/// Pure state machine: it takes [Utterance]s (already parsed from audio at the
/// edge) and mutates only flow position plus the field's proposed value via
/// the surface's propose callbacks. No Flutter, no audio — fully unit-tested.
class GuidedDictationController {
  GuidedDictationController(AgentSurface surface)
      : _fields = surface.fillable;

  final List<AgentField> _fields;
  int _index = 0;
  bool _complete = false;
  bool _awaitingConfirm = false;

  GuidedState get state => GuidedState(
        field: _complete || _index >= _fields.length ? null : _fields[_index],
        index: _index,
        total: _fields.length,
        awaitingConfirm: _awaitingConfirm,
        complete: _complete || _fields.isEmpty,
      );

  GuidedOutcome apply(Utterance utterance) {
    if (_complete || _fields.isEmpty) return GuidedOutcome.completed;

    return switch (utterance) {
      CommandUtterance(:final command) => _command(command),
      NumberUtterance(:final value) => _number(value),
      PairUtterance(:final first, :final second) => _pair(first, second),
      UnclearUtterance() => GuidedOutcome.unclear,
    };
  }

  GuidedOutcome _command(DictationCommand command) {
    switch (command) {
      case DictationCommand.next:
        return _advance();
      case DictationCommand.skip:
        _awaitingConfirm = false;
        return _advance(outcome: GuidedOutcome.skipped);
      case DictationCommand.redo:
        _awaitingConfirm = false;
        return GuidedOutcome.redone;
      case DictationCommand.back:
        if (_index > 0) _index--;
        _awaitingConfirm = false;
        return GuidedOutcome.wentBack;
      case DictationCommand.stop:
        _complete = true;
        _awaitingConfirm = false;
        return GuidedOutcome.completed;
    }
  }

  GuidedOutcome _number(num value) {
    final field = _fields[_index];
    final propose = field.proposeNumber;
    if (propose == null) return GuidedOutcome.unclear;
    propose(value);
    _awaitingConfirm = true;
    return GuidedOutcome.proposed;
  }

  GuidedOutcome _pair(int first, int second) {
    final field = _fields[_index];
    final propose = field.proposePair;
    if (propose == null) return GuidedOutcome.unclear;
    propose(first, second);
    _awaitingConfirm = true;
    return GuidedOutcome.proposed;
  }

  GuidedOutcome _advance({GuidedOutcome outcome = GuidedOutcome.advanced}) {
    _awaitingConfirm = false;
    if (_index >= _fields.length - 1) {
      _complete = true;
      return GuidedOutcome.completed;
    }
    _index++;
    return outcome;
  }
}
