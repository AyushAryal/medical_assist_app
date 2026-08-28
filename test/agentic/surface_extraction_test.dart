import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/agentic/drivers/surface_extraction.dart';
import 'package:medical_app/core/agentic/agent_surface.dart';

void main() {
  late Map<String, Object> proposed;
  late AgentSurface surface;
  const extractor = SurfaceExtraction();

  setUp(() {
    proposed = <String, Object>{};
    surface = AgentSurface(<AgentField>[
      AgentField(
        id: 'bp',
        label: 'Blood pressure',
        kind: AgentFieldKind.pair,
        aliases: const <String>['bp'],
        min: 40,
        max: 300,
        proposePair: (a, b) => proposed['bp'] = '$a/$b',
      ),
      AgentField(
        id: 'pulse',
        label: 'Pulse',
        kind: AgentFieldKind.integer,
        aliases: const <String>['heart rate', 'hr'],
        min: 20,
        max: 300,
        proposeNumber: (v) => proposed['pulse'] = v,
      ),
      AgentField(
        id: 'spo2',
        label: 'Oxygen saturation',
        kind: AgentFieldKind.integer,
        aliases: const <String>['sats', 'sat'],
        min: 50,
        max: 100,
        proposeNumber: (v) => proposed['spo2'] = v,
      ),
      AgentField(
        id: 'temp',
        label: 'Temperature',
        kind: AgentFieldKind.decimal,
        aliases: const <String>['temp'],
        min: 30,
        max: 45,
        proposeNumber: (v) => proposed['temp'] = v,
      ),
    ]);
  });

  test('fills a well-formed extraction', () {
    final result = extractor.apply(<String, Object?>{
      'bp': '120/80',
      'pulse': 110,
      'temp': 38.5,
    }, surface);
    expect(proposed['bp'], '120/80');
    expect(proposed['pulse'], 110);
    expect(proposed['temp'], 38.5);
    expect(result.filled, containsAll(<String>['bp', 'pulse', 'temp']));
  });

  test('accepts a pair as a list or a systolic/diastolic map', () {
    extractor.apply(<String, Object?>{'bp': <int>[118, 76]}, surface);
    expect(proposed['bp'], '118/76');
    proposed.clear();
    extractor.apply(<String, Object?>{
      'bp': <String, int>{'systolic': 130, 'diastolic': 85},
    }, surface);
    expect(proposed['bp'], '130/85');
  });

  test('refuses a value outside the plausible bounds', () {
    final result = extractor.apply(<String, Object?>{'pulse': 900}, surface);
    expect(proposed.containsKey('pulse'), isFalse);
    expect(result.rejected, contains('pulse'));
  });

  test('drops a key that matches no field', () {
    final result = extractor.apply(<String, Object?>{'mood': 'unwell'}, surface);
    expect(result.unknown, contains('mood'));
    expect(proposed, isEmpty);
  });

  test('routes an alias key to its field', () {
    extractor.apply(<String, Object?>{'sats': 94}, surface);
    expect(proposed['spo2'], 94);
  });

  test('reads a spelled-out number from a string value', () {
    extractor.apply(<String, Object?>{'pulse': 'eighty eight'}, surface);
    expect(proposed['pulse'], 88);
  });

  test('a null value is left blank, not an error', () {
    final result =
        extractor.apply(<String, Object?>{'temp': null, 'pulse': 72}, surface);
    expect(proposed.containsKey('temp'), isFalse);
    expect(proposed['pulse'], 72);
    expect(result.rejected, isEmpty);
  });

  test('a number for a pair field is refused, not mis-filled', () {
    final result = extractor.apply(<String, Object?>{'bp': 120}, surface);
    expect(proposed.containsKey('bp'), isFalse);
    expect(result.rejected, contains('bp'));
  });
}
