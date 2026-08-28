import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/features/vitals/guided/spoken_value.dart';

void main() {
  const parser = SpokenValueParser();

  group('digit numbers — the form Whisper usually produces', () {
    test('a plain integer', () {
      expect(parser.parse('72'), const NumberUtterance(72));
    });

    test('a decimal', () {
      expect(parser.parse('98.6'), const NumberUtterance(98.6));
    });

    test('a number wrapped in filler words', () {
      expect(parser.parse('pulse is 88'), const NumberUtterance(88));
      expect(parser.parse('about 120'), const NumberUtterance(120));
    });
  });

  group('blood-pressure pairs', () {
    test('"120 over 80"', () {
      expect(parser.parse('120 over 80'), const PairUtterance(120, 80));
    });

    test('alternative separators', () {
      expect(parser.parse('118 on 76'), const PairUtterance(118, 76));
      expect(parser.parse('130 / 85'), const PairUtterance(130, 85));
      expect(parser.parse('140 by 90'), const PairUtterance(140, 90));
    });
  });

  group('commands', () {
    test('advance and skip', () {
      expect(parser.parse('next'), const CommandUtterance(DictationCommand.next));
      expect(parser.parse('okay'), const CommandUtterance(DictationCommand.next));
      expect(parser.parse('skip'), const CommandUtterance(DictationCommand.skip));
    });

    test('redo, back and stop', () {
      expect(parser.parse('scratch that'),
          const CommandUtterance(DictationCommand.redo));
      expect(parser.parse('again'),
          const CommandUtterance(DictationCommand.redo));
      expect(parser.parse('go back'),
          const CommandUtterance(DictationCommand.back));
      expect(parser.parse('done'),
          const CommandUtterance(DictationCommand.stop));
    });

    test('a number is never swallowed by a stray command word', () {
      // "confirm" is a next-word, but a value was clearly spoken.
      expect(parser.parse('confirm 98'), const NumberUtterance(98));
    });
  });

  group('spoken number words', () {
    test('tens and units', () {
      expect(parser.parse('ninety eight'), const NumberUtterance(98));
      expect(parser.parse('seventy two'), const NumberUtterance(72));
      expect(parser.parse('sixty'), const NumberUtterance(60));
    });

    test('colloquial hundreds for BP', () {
      expect(parser.parse('one twenty'), const NumberUtterance(120));
    });

    test('decimals read digit by digit', () {
      expect(parser.parse('thirty eight point six'),
          const NumberUtterance(38.6));
      expect(parser.parse('ninety eight point six'),
          const NumberUtterance(98.6));
    });
  });

  group('declines rather than guesses — the safety property', () {
    test('empty and pure filler', () {
      expect(parser.parse(''), isA<UnclearUtterance>());
      expect(parser.parse('um the patient looks'), isA<UnclearUtterance>());
    });

    test('two bare numbers with no "over" are ambiguous, not a value', () {
      // Could be a mis-heard pair, or two readings — never assume.
      expect(parser.parse('120 80'), isA<UnclearUtterance>());
    });

    test('a lone decimal fraction with no whole part', () {
      expect(parser.parse('point six'), isA<UnclearUtterance>());
    });

    test('unrecognised number-word soup', () {
      expect(parser.parse('a few hundred maybe'), isA<UnclearUtterance>());
    });

    test('the unclear result carries what was heard, for a repeat prompt', () {
      final result = parser.parse('mumble mumble');
      expect(result, isA<UnclearUtterance>());
      expect((result as UnclearUtterance).heard, 'mumble mumble');
    });
  });

  group('case and whitespace are normalised', () {
    test('upper case and padding', () {
      expect(parser.parse('  NEXT  '),
          const CommandUtterance(DictationCommand.next));
      expect(parser.parse('120 OVER 80'), const PairUtterance(120, 80));
    });
  });
}
