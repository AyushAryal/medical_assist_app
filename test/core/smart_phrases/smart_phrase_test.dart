import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/core/smart_phrases/smart_phrase.dart';

void main() {
  SmartPhraseController controllerAt(String text, int cursor) {
    final controller = SmartPhraseController(text: text);
    controller.selection = TextSelection.collapsed(offset: cursor);
    return controller;
  }

  group('activeQuery', () {
    test('sees the word being typed after a backslash', () {
      final c = controllerAt('how is \\pa', 10);
      addTearDown(c.dispose);
      final query = c.activeQuery;
      expect(query, isNotNull);
      expect(query!.query, 'pa');
    });

    test('ends at a space — a completed word is not a live query', () {
      final c = controllerAt('\\pat done', 9);
      addTearDown(c.dispose);
      expect(c.activeQuery, isNull);
    });

    test('is null when there is no backslash', () {
      final c = controllerAt('just words', 10);
      addTearDown(c.dispose);
      expect(c.activeQuery, isNull);
    });
  });

  group('insertResolved', () {
    test('replaces the \\query with the display text and records the payload', () {
      final c = controllerAt('how is \\pat', 11);
      addTearDown(c.dispose);

      c.insertResolved(const SmartPhraseValue(
        display: 'Ramesh Thapa',
        kind: 'patient',
        payload: 'patient-123',
      ));

      expect(c.text, 'how is Ramesh Thapa ');
      expect(c.payloadOf('patient'), 'patient-123');
    });

    test('a plain text expansion inserts text but records no token', () {
      final c = controllerAt('\\ros', 4);
      addTearDown(c.dispose);

      c.insertResolved(const SmartPhraseValue(
        display: 'No fever, no cough.',
        kind: 'text',
      ));

      expect(c.text, 'No fever, no cough. ');
      expect(c.tokens, isEmpty);
    });

    test('deleting the inserted patient text drops its payload', () {
      final c = controllerAt('\\pat', 4);
      addTearDown(c.dispose);
      c.insertResolved(const SmartPhraseValue(
        display: 'Ramesh Thapa',
        kind: 'patient',
        payload: 'patient-123',
      ));
      expect(c.payloadOf('patient'), 'patient-123');

      // The clinician clears the field.
      c.value = const TextEditingValue(text: '');
      expect(c.payloadOf('patient'), isNull);
    });
  });
}
