import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/cohort/cohort_query.dart';
import 'package:medical_app/ai/schema/field_registry.dart';

/// Holds the two table vocabularies together.
///
/// The cohort matcher and the schema registry each describe the same tables —
/// one for filtering, one for analysis — and they were written at different
/// times for different jobs. That is fine until a synonym is added to one and
/// not the other, at which point "how many visits" and "average visit length"
/// disagree about what a visit is. This test is the tripwire: every cohort
/// trigger word must either resolve to the *same* table in the registry or to
/// nothing, never to a different one.
void main() {
  const bridge = <QueryEntity, String>{
    QueryEntity.patients: 'patients',
    QueryEntity.appointments: 'appointments',
    QueryEntity.visits: 'encounters',
    QueryEntity.vitals: 'vitals',
    QueryEntity.notes: 'clinical_notes',
    QueryEntity.files: 'attachments',
  };

  test('every cohort entity has a registry table', () {
    for (final entity in QueryEntity.values) {
      final table = FieldRegistry.byName(bridge[entity]!);
      expect(table, isNotNull, reason: entity.name);
    }
  });

  test('no trigger word points the two vocabularies at different tables', () {
    for (final entity in QueryEntity.values) {
      for (final word in entity.triggerWords) {
        final resolved = FieldRegistry.resolveTable(word);
        if (resolved == null) continue; // unknown to the registry is fine
        expect(
          resolved.table.name,
          bridge[entity],
          reason: '"$word" filters ${entity.name} but analyses '
              '${resolved.table.name} — the same word must mean the same '
              'table everywhere',
        );
      }
    }
  });
}
