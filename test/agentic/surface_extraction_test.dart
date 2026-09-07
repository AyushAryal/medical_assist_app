import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/agentic/drivers/surface_extraction.dart';
import 'package:medical_app/core/agentic/agent_surface.dart';

void main() {
  late AgentSurface surface;
  const extractor = SurfaceExtraction();

  setUp(() {
    surface = AgentSurface(<AgentField>[
      AgentField(
        id: 'bp',
        label: 'Blood pressure',
        kind: AgentFieldKind.pair,
        aliases: const <String>['bp'],
        min: 40,
        max: 300,
        proposePair: (a, b) {},
      ),
      AgentField(
        id: 'pulse',
        label: 'Pulse',
        kind: AgentFieldKind.integer,
        aliases: const <String>['heart rate', 'hr'],
        min: 20,
        max: 300,
        proposeNumber: (v) {},
      ),
      AgentField(
        id: 'spo2',
        label: 'Oxygen saturation',
        kind: AgentFieldKind.integer,
        aliases: const <String>['sats', 'sat'],
        min: 50,
        max: 100,
        proposeNumber: (v) {},
      ),
      AgentField(
        id: 'temp',
        label: 'Temperature',
        kind: AgentFieldKind.decimal,
        aliases: const <String>['temp'],
        min: 30,
        max: 45,
        proposeNumber: (v) {},
      ),
    ]);
  });

  test('validates a well-formed extraction without writing', () {
    final result = extractor.apply(<String, Object?>{
      'bp': '120/80',
      'pulse': 110,
      'temp': 38.5,
    }, surface);
    expect(result.values['bp']?.pair, (120, 80));
    expect(result.values['pulse']?.number, 110);
    expect(result.values['temp']?.number, 38.5);
    expect(result.values['bp']?.display, '120/80');
  });

  test('accepts a pair as a list or a systolic/diastolic map', () {
    expect(
      extractor.apply(<String, Object?>{'bp': <int>[118, 76]}, surface)
          .values['bp']?.pair,
      (118, 76),
    );
    expect(
      extractor.apply(<String, Object?>{
        'bp': <String, int>{'systolic': 130, 'diastolic': 85},
      }, surface).values['bp']?.pair,
      (130, 85),
    );
  });

  test('refuses a value outside the plausible bounds', () {
    final result = extractor.apply(<String, Object?>{'pulse': 900}, surface);
    expect(result.values.containsKey('pulse'), isFalse);
    expect(result.rejected, contains('pulse'));
  });

  test('drops a key that matches no field', () {
    final result = extractor.apply(<String, Object?>{'mood': 'unwell'}, surface);
    expect(result.unknown, contains('mood'));
    expect(result.values, isEmpty);
  });

  test('routes an alias key to its field', () {
    expect(
      extractor.apply(<String, Object?>{'sats': 94}, surface)
          .values['spo2']?.number,
      94,
    );
  });

  test('reads a spelled-out number from a string value', () {
    expect(
      extractor.apply(<String, Object?>{'pulse': 'eighty eight'}, surface)
          .values['pulse']?.number,
      88,
    );
  });

  test('a null value is left blank, not an error', () {
    final result =
        extractor.apply(<String, Object?>{'temp': null, 'pulse': 72}, surface);
    expect(result.values.containsKey('temp'), isFalse);
    expect(result.values['pulse']?.number, 72);
    expect(result.rejected, isEmpty);
  });

  test('a number for a pair field is refused, not mis-read', () {
    final result = extractor.apply(<String, Object?>{'bp': 120}, surface);
    expect(result.values.containsKey('bp'), isFalse);
    expect(result.rejected, contains('bp'));
  });
}
