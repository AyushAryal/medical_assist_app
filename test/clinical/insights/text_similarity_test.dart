import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/core/utils/text_similarity.dart';

void main() {
  group('jaroWinkler', () {
    test('identical strings score 1', () {
      expect(TextSimilarity.jaroWinkler('aryal', 'aryal'), 1.0);
    });

    test('a transposition costs less than two substitutions', () {
      // The reason for Jaro over edit distance: `Aryal`/`Aryla` is one slip of
      // the fingers, and Levenshtein charges it as two errors.
      expect(
        TextSimilarity.jaroWinkler('aryal', 'aryla'),
        greaterThan(0.9),
      );
    });

    test('a shared prefix is rewarded', () {
      // People mistype and abbreviate the ends of names far more than the
      // beginnings, so agreement at the start is stronger evidence.
      final sharedPrefix = TextSimilarity.jaroWinkler('shrestha', 'shresth');
      final sharedSuffix = TextSimilarity.jaroWinkler('hrestha', 'shrestha');
      expect(sharedPrefix, greaterThan(sharedSuffix));
    });

    test('the prefix bonus is withheld from weak matches', () {
      // Otherwise every unrelated name sharing a first letter is inflated,
      // which on a large register is most of them.
      final weak = TextSimilarity.jaroWinkler('anita', 'prakash');
      expect(weak, lessThan(0.7));
    });

    test('unrelated names still score well above zero', () {
      // Pinned because it is the fact that sets every threshold in
      // DuplicateDetector. Jaro does not approach 0 for unrelated strings —
      // measured, these sit between 0.45 and 0.62, which is why
      // `_bothHalvesThreshold` is 0.72 and not something that merely looks
      // generous.
      for (final pair in <List<String>>[
        <String>['sita', 'bikash'],
        <String>['anita', 'prakash'],
        <String>['aryal', 'gurung'],
      ]) {
        final score = TextSimilarity.jaroWinkler(pair.first, pair.last);
        expect(score, greaterThan(0.4), reason: pair.join(' vs '));
        expect(score, lessThan(0.65), reason: pair.join(' vs '));
      }
    });

    test('an empty string scores 0 rather than throwing', () {
      expect(TextSimilarity.jaroWinkler('', 'aryal'), 0.0);
      expect(TextSimilarity.jaroWinkler('aryal', ''), 0.0);
      expect(TextSimilarity.jaroWinkler('', ''), 1.0);
    });
  });

  group('normaliseName', () {
    test('folds case, accents and punctuation', () {
      expect(TextSimilarity.normaliseName("O'Brien"), 'obrien');
      expect(TextSimilarity.normaliseName('OBrien'), 'obrien');
      expect(TextSimilarity.normaliseName('o brien'), 'obrien');
      expect(TextSimilarity.normaliseName('Müller'), 'muller');
      expect(TextSimilarity.normaliseName('José'), 'jose');
      expect(TextSimilarity.normaliseName('  Aryal  '), 'aryal');
    });

    test('collapses a hyphenated name to one form', () {
      expect(
        TextSimilarity.normaliseName('Smith-Jones'),
        TextSimilarity.normaliseName('Smith Jones'),
      );
    });
  });

  group('normalisePhone', () {
    test('compares on the last nine digits', () {
      expect(
        TextSimilarity.normalisePhone('+977 98-1234567'),
        TextSimilarity.normalisePhone('09812 34567'),
      );
    });

    test('rejects anything too short to be a phone number', () {
      expect(TextSimilarity.normalisePhone('1234'), isNull);
      expect(TextSimilarity.normalisePhone('n/a'), isNull);
      expect(TextSimilarity.normalisePhone(null), isNull);
    });

    test('keeps a short-but-plausible number intact', () {
      expect(TextSimilarity.normalisePhone('5551234'), '5551234');
    });
  });

  group('consonantSkeleton', () {
    test('two transliterations of one name share a skeleton', () {
      expect(
        TextSimilarity.consonantSkeleton('Mohammed'),
        TextSimilarity.consonantSkeleton('Muhammad'),
      );
      expect(
        TextSimilarity.consonantSkeleton('Krishna'),
        TextSimilarity.consonantSkeleton('Krshna'),
      );
    });

    test('the first letter is kept even when it is a vowel', () {
      expect(TextSimilarity.consonantSkeleton('Anita'), 'ant');
    });

    test('genuinely different names do not collide', () {
      expect(
        TextSimilarity.consonantSkeleton('Anita'),
        isNot(TextSimilarity.consonantSkeleton('Prakash')),
      );
    });

    test('an empty name yields an empty skeleton', () {
      expect(TextSimilarity.consonantSkeleton(''), '');
      expect(TextSimilarity.consonantSkeleton('...'), '');
    });
  });
}
