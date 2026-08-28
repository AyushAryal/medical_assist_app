import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/core/agentic/agent_surface.dart';
import 'package:medical_app/agentic/drivers/guided_dictation_controller.dart';
import 'package:medical_app/agentic/drivers/spoken_value.dart';

void main() {
  // A fake vitals surface whose propose callbacks record what was set.
  late Map<String, Object> proposed;
  late AgentSurface surface;

  setUp(() {
    proposed = <String, Object>{};
    surface = AgentSurface(<AgentField>[
      AgentField(
        id: 'bp',
        label: 'Blood pressure',
        kind: AgentFieldKind.pair,
        unit: 'mmHg',
        proposePair: (a, b) => proposed['bp'] = '$a/$b',
      ),
      AgentField(
        id: 'pulse',
        label: 'Pulse',
        kind: AgentFieldKind.integer,
        unit: 'bpm',
        proposeNumber: (v) => proposed['pulse'] = v,
      ),
      AgentField(
        id: 'temp',
        label: 'Temperature',
        kind: AgentFieldKind.decimal,
        unit: '°C',
        proposeNumber: (v) => proposed['temp'] = v,
      ),
      // Display-only — no propose callback, so the flow must not stop on it.
      const AgentField(id: 'note', label: 'Note', kind: AgentFieldKind.text),
    ]);
  });

  test('walks only the fillable fields, in order', () {
    final c = GuidedDictationController(surface);
    expect(c.state.total, 3);
    expect(c.state.field?.id, 'bp');
  });

  test('a full pass proposes each value and completes', () {
    final c = GuidedDictationController(surface);

    expect(c.apply(const PairUtterance(120, 80)), GuidedOutcome.proposed);
    expect(proposed['bp'], '120/80');
    expect(c.state.awaitingConfirm, isTrue);

    expect(c.apply(const CommandUtterance(DictationCommand.next)),
        GuidedOutcome.advanced);
    expect(c.state.field?.id, 'pulse');

    expect(c.apply(const NumberUtterance(88)), GuidedOutcome.proposed);
    expect(proposed['pulse'], 88);

    expect(c.apply(const CommandUtterance(DictationCommand.next)),
        GuidedOutcome.advanced);
    expect(c.apply(const NumberUtterance(38.6)), GuidedOutcome.proposed);
    expect(proposed['temp'], 38.6);

    // "next" on the last field finishes.
    expect(c.apply(const CommandUtterance(DictationCommand.next)),
        GuidedOutcome.completed);
    expect(c.state.complete, isTrue);
    expect(c.state.field, isNull);
  });

  test('a single number on a pair field is refused, not mis-filled', () {
    final c = GuidedDictationController(surface);
    expect(c.apply(const NumberUtterance(120)), GuidedOutcome.unclear);
    expect(proposed.containsKey('bp'), isFalse);
  });

  test('skip leaves the field empty and advances', () {
    final c = GuidedDictationController(surface);
    expect(c.apply(const CommandUtterance(DictationCommand.skip)),
        GuidedOutcome.skipped);
    expect(proposed.containsKey('bp'), isFalse);
    expect(c.state.field?.id, 'pulse');
  });

  test('redo stays on the field for a re-dictation', () {
    final c = GuidedDictationController(surface);
    c.apply(const PairUtterance(120, 80));
    expect(c.apply(const CommandUtterance(DictationCommand.redo)),
        GuidedOutcome.redone);
    expect(c.state.field?.id, 'bp');
    expect(c.state.awaitingConfirm, isFalse);
  });

  test('back steps to the previous field', () {
    final c = GuidedDictationController(surface);
    c.apply(const CommandUtterance(DictationCommand.next)); // to pulse
    expect(c.apply(const CommandUtterance(DictationCommand.back)),
        GuidedOutcome.wentBack);
    expect(c.state.field?.id, 'bp');
  });

  test('back on the first field stays put', () {
    final c = GuidedDictationController(surface);
    c.apply(const CommandUtterance(DictationCommand.back));
    expect(c.state.field?.id, 'bp');
  });

  test('stop ends the flow early', () {
    final c = GuidedDictationController(surface);
    expect(c.apply(const CommandUtterance(DictationCommand.stop)),
        GuidedOutcome.completed);
    expect(c.state.complete, isTrue);
  });

  test('an unclear utterance holds on the current field', () {
    final c = GuidedDictationController(surface);
    expect(c.apply(const UnclearUtterance('mumble')), GuidedOutcome.unclear);
    expect(c.state.field?.id, 'bp');
  });

  test('a surface with no fillable fields is complete immediately', () {
    final empty = AgentSurface(<AgentField>[
      const AgentField(id: 'note', label: 'Note', kind: AgentFieldKind.text),
    ]);
    final c = GuidedDictationController(empty);
    expect(c.state.complete, isTrue);
    expect(c.apply(const NumberUtterance(1)), GuidedOutcome.completed);
  });
}
