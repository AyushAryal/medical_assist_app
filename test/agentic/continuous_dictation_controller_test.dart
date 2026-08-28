import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/agentic/drivers/continuous_dictation_controller.dart';
import 'package:medical_app/core/agentic/agent_surface.dart';

void main() {
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
        aliases: const <String>['bp', 'pressure'],
        min: 40,
        max: 300,
        proposePair: (a, b) => proposed['bp'] = '$a/$b',
      ),
      AgentField(
        id: 'pulse',
        label: 'Pulse',
        kind: AgentFieldKind.integer,
        unit: 'bpm',
        aliases: const <String>['heart rate', 'hr'],
        min: 20,
        max: 300,
        proposeNumber: (v) => proposed['pulse'] = v,
      ),
      AgentField(
        id: 'temp',
        label: 'Temperature',
        kind: AgentFieldKind.decimal,
        unit: '°C',
        aliases: const <String>['temp'],
        min: 30,
        max: 45,
        proposeNumber: (v) => proposed['temp'] = v,
      ),
      AgentField(
        id: 'glucose',
        label: 'Glucose',
        kind: AgentFieldKind.decimal,
        aliases: const <String>['sugar'],
        min: 1,
        max: 40,
        proposeNumber: (v) => proposed['glucose'] = v,
      ),
    ]);
  });

  test('routes a value to the field named in the phrase', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('pulse 88'), ContinuousOutcome.filled);
    expect(proposed['pulse'], 88);
    // Routing did not touch the first (pending) field.
    expect(proposed.containsKey('bp'), isFalse);
    expect(c.current?.id, 'bp');
  });

  test('routes a spoken pair', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('blood pressure 120 over 80'), ContinuousOutcome.filled);
    expect(proposed['bp'], '120/80');
  });

  test('an unnamed value fills the current pending field', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('120 over 80'), ContinuousOutcome.filled); // current is bp
    expect(proposed['bp'], '120/80');
    expect(c.apply('88'), ContinuousOutcome.filled); // current now pulse
    expect(proposed['pulse'], 88);
  });

  test('a short alias does not match inside a number word', () {
    // "hr" must not be found inside "three".
    final c = ContinuousDictationController(surface);
    c.apply('temp 38.6'); // name the temp so routing is unambiguous
    expect(proposed['temp'], 38.6);
  });

  test('sanitises: an implausible value is rejected, not entered', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('pulse 880'), ContinuousOutcome.rejected);
    expect(proposed.containsKey('pulse'), isFalse);
    expect(
      c.entries.firstWhere((e) => e.field.id == 'pulse').status,
      FieldStatus.rejected,
    );
  });

  test('skip by name leaves a field empty', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('skip glucose'), ContinuousOutcome.skipped);
    expect(proposed.containsKey('glucose'), isFalse);
    expect(
      c.entries.firstWhere((e) => e.field.id == 'glucose').status,
      FieldStatus.skipped,
    );
  });

  test('bare skip skips the current field', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('skip'), ContinuousOutcome.skipped); // current is bp
    expect(c.current?.id, 'pulse');
  });

  test('redo clears a named field back to pending', () {
    final c = ContinuousDictationController(surface);
    c.apply('pulse 88');
    expect(c.apply('redo pulse'), ContinuousOutcome.cleared);
    expect(
      c.entries.firstWhere((e) => e.field.id == 'pulse').status,
      FieldStatus.pending,
    );
  });

  test('"done" stops the session', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('done'), ContinuousOutcome.stopped);
    expect(c.complete, isTrue);
  });

  test('tracks filled count and completion', () {
    final c = ContinuousDictationController(surface);
    expect(c.total, 4);
    c.apply('blood pressure 120 over 80');
    c.apply('pulse 88');
    c.apply('temp 38.6');
    expect(c.filledCount, 3);
    expect(c.complete, isFalse);
    c.apply('skip sugar');
    expect(c.complete, isTrue); // nothing pending
  });

  test('a number for a pair field is refused as unclear', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('blood pressure 120'), ContinuousOutcome.unclear);
    expect(proposed.containsKey('bp'), isFalse);
  });

  group('one-speech entry', () {
    test('splits a whole transcript into per-field phrases', () {
      final phrases = ContinuousDictationController.splitPhrases(
        'so the blood pressure 120 over 80 pulse 88 temp 38.6 skip sugar done',
        surface,
      );
      expect(phrases, <String>[
        'blood pressure 120 over 80',
        'pulse 88',
        'temp 38.6',
        'skip sugar',
        'done',
      ]);
    });

    test('a whole spoken set fills the record in one pass', () {
      final c = ContinuousDictationController(surface);
      final landed = c.applyTranscript(
        'blood pressure 120 over 80 pulse 88 temp 38.6 skip sugar',
      );
      expect(landed, isTrue);
      expect(proposed['bp'], '120/80');
      expect(proposed['pulse'], 88);
      expect(proposed['temp'], 38.6);
      expect(c.complete, isTrue); // bp/pulse/temp filled, glucose skipped
    });

    test('"done" mid-transcript stops the rest', () {
      final c = ContinuousDictationController(surface);
      c.applyTranscript('pulse 88 done temp 38.6');
      expect(proposed['pulse'], 88);
      expect(proposed.containsKey('temp'), isFalse);
    });
  });
}
