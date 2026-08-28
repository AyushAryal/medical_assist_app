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

  FieldEntry entry(ContinuousDictationController c, String id) =>
      c.entries.firstWhere((e) => e.field.id == id);

  test('stages a value against the field named in the phrase', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('pulse 88'), ContinuousOutcome.filled);
    expect(entry(c, 'pulse').number, 88);
    // Nothing is written to the form yet — staged only.
    expect(proposed, isEmpty);
    // And the unnamed first field is untouched.
    expect(entry(c, 'bp').status, FieldStatus.pending);
    expect(c.current?.id, 'bp');
  });

  test('commit writes every staged value into the form', () {
    final c = ContinuousDictationController(surface);
    c.apply('blood pressure 120 over 80');
    c.apply('pulse 88');
    expect(proposed, isEmpty); // still staged
    c.commit();
    expect(proposed['bp'], '120/80');
    expect(proposed['pulse'], 88);
  });

  test('stages a spoken pair', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('blood pressure 120 over 80'), ContinuousOutcome.filled);
    expect(entry(c, 'bp').pair, (120, 80));
  });

  test('an unnamed value fills the current pending field', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('120 over 80'), ContinuousOutcome.filled); // current is bp
    expect(entry(c, 'bp').pair, (120, 80));
    expect(c.apply('88'), ContinuousOutcome.filled); // current now pulse
    expect(entry(c, 'pulse').number, 88);
  });

  test('a short alias does not match inside a number word', () {
    final c = ContinuousDictationController(surface);
    c.apply('temp 38.6');
    expect(entry(c, 'temp').number, 38.6);
  });

  test('sanitises: an implausible value is rejected, not staged', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('pulse 880'), ContinuousOutcome.rejected);
    expect(entry(c, 'pulse').number, isNull);
    expect(entry(c, 'pulse').status, FieldStatus.rejected);
  });

  test('skip by name leaves a field empty', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('skip glucose'), ContinuousOutcome.skipped);
    expect(entry(c, 'glucose').status, FieldStatus.skipped);
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
    expect(entry(c, 'pulse').status, FieldStatus.pending);
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
    expect(c.complete, isTrue);
  });

  test('a number for a pair field is refused as unclear', () {
    final c = ContinuousDictationController(surface);
    expect(c.apply('blood pressure 120'), ContinuousOutcome.unclear);
    expect(entry(c, 'bp').status, FieldStatus.pending);
  });

  group('transcript cleanup', () {
    test('collapses the repeated tokens a small model emits', () {
      expect(
        ContinuousDictationController.cleanTranscript('21 21 21 21 21'),
        '21',
      );
      expect(
        ContinuousDictationController.cleanTranscript('pulse 88 88'),
        'pulse 88',
      );
      expect(
        ContinuousDictationController.cleanTranscript('120 over 80'),
        '120 over 80',
      );
    });

    test('a cleaned repeat is a usable value', () {
      final c = ContinuousDictationController(surface);
      final cleaned = ContinuousDictationController.cleanTranscript(
        'pulse 88 88 88 88',
      );
      expect(c.apply(cleaned), ContinuousOutcome.filled);
      expect(entry(c, 'pulse').number, 88);
    });
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

    test('a whole spoken set stages the record, commit writes it', () {
      final c = ContinuousDictationController(surface);
      final landed = c.applyTranscript(
        'blood pressure 120 over 80 pulse 88 temp 38.6 skip sugar',
      );
      expect(landed, isTrue);
      c.commit();
      expect(proposed['bp'], '120/80');
      expect(proposed['pulse'], 88);
      expect(proposed['temp'], 38.6);
      expect(c.complete, isTrue);
    });

    test('"done" mid-transcript stops the rest', () {
      final c = ContinuousDictationController(surface);
      c.applyTranscript('pulse 88 done temp 38.6');
      c.commit();
      expect(proposed['pulse'], 88);
      expect(proposed.containsKey('temp'), isFalse);
    });
  });
}
