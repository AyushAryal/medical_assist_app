import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/insights/duplicate_detector.dart';

void main() {
  PatientIdentity patient({
    String id = 'x',
    required String given,
    required String family,
    DateTime? dob,
    bool estimated = false,
    String? phone,
    String? nationalId,
    String? sex,
  }) =>
      PatientIdentity(
        id: id,
        givenName: given,
        familyName: family,
        dateOfBirth: dob,
        dobIsEstimated: estimated,
        phone: phone,
        nationalId: nationalId,
        sexAtBirth: sex,
      );

  double scoreOf(PatientIdentity a, PatientIdentity b) =>
      DuplicateDetector.compare(a, b).score;

  group('catches the duplicates that matter', () {
    test('the same name and date of birth scores as a strong match', () {
      final score = scoreOf(
        patient(id: 'a', given: 'Sita', family: 'Aryal',
            dob: DateTime(1990, 4, 2)),
        patient(id: 'b', given: 'Sita', family: 'Aryal',
            dob: DateTime(1990, 4, 2)),
      );
      expect(score, greaterThanOrEqualTo(DuplicateDetector.strongThreshold));
    });

    test('a transposed surname still matches', () {
      final score = scoreOf(
        patient(id: 'a', given: 'Sita', family: 'Aryal',
            dob: DateTime(1990, 4, 2)),
        patient(id: 'b', given: 'Sita', family: 'Aryla',
            dob: DateTime(1990, 4, 2)),
      );
      expect(score, greaterThanOrEqualTo(DuplicateDetector.reviewThreshold));
    });

    test('given and family names swapped is caught', () {
      final result = DuplicateDetector.compare(
        patient(id: 'a', given: 'Aryal', family: 'Sita',
            dob: DateTime(1990, 4, 2)),
        patient(id: 'b', given: 'Sita', family: 'Aryal',
            dob: DateTime(1990, 4, 2)),
      );
      expect(result.score, greaterThanOrEqualTo(DuplicateDetector.reviewThreshold));
      expect(result.reasons, contains('Given and family names appear swapped'));
    });

    test('a different transliteration of one name is caught', () {
      final result = DuplicateDetector.compare(
        patient(id: 'a', given: 'Mohammed', family: 'Khan'),
        patient(id: 'b', given: 'Muhammad', family: 'Khan'),
      );
      expect(result.score, greaterThanOrEqualTo(DuplicateDetector.reviewThreshold));
      expect(result.reasons, contains('Same name, spelled differently'));
    });

    test('a shared phone number lifts a merely similar name', () {
      final withPhone = scoreOf(
        patient(id: 'a', given: 'Ram', family: 'Thapa', phone: '+977 9812345678'),
        patient(id: 'b', given: 'Rama', family: 'Thapa', phone: '9812345678'),
      );
      final withoutPhone = scoreOf(
        patient(id: 'a', given: 'Ram', family: 'Thapa'),
        patient(id: 'b', given: 'Rama', family: 'Thapa'),
      );
      expect(withPhone, greaterThan(withoutPhone));
    });

    test('a matching national ID is near-certain on its own', () {
      final result = DuplicateDetector.compare(
        patient(id: 'a', given: 'Sita', family: 'Aryal', nationalId: '123456789'),
        // Married name change: nothing else matches.
        patient(id: 'b', given: 'Sita', family: 'Sharma', nationalId: '123456789'),
      );
      expect(result.isNearCertain, isTrue);
      expect(result.score, greaterThanOrEqualTo(0.95));
    });
  });

  group('does not cry wolf', () {
    test('two unrelated people do not reach the review threshold', () {
      expect(
        scoreOf(
          patient(id: 'a', given: 'Sita', family: 'Aryal'),
          patient(id: 'b', given: 'Bikash', family: 'Gurung'),
        ),
        lessThan(DuplicateDetector.reviewThreshold),
      );
    });

    test('two confirmed different birth dates override an identical name', () {
      // Families reuse names. A father and son with the same name and
      // different birth dates are two people, and flagging them is the failure
      // that makes staff stop reading the warning.
      expect(
        scoreOf(
          patient(id: 'a', given: 'Ram', family: 'Thapa',
              dob: DateTime(1962, 1, 15)),
          patient(id: 'b', given: 'Ram', family: 'Thapa',
              dob: DateTime(1991, 7, 3)),
        ),
        lessThan(DuplicateDetector.reviewThreshold),
      );
    });

    test('a shared surname alone is not a duplicate', () {
      expect(
        scoreOf(
          patient(id: 'a', given: 'Anita', family: 'Shrestha'),
          patient(id: 'b', given: 'Prakash', family: 'Shrestha'),
        ),
        lessThan(DuplicateDetector.reviewThreshold),
      );
    });

    test('an estimated birth date is compared by year, not by day', () {
      // An approximate age is stored as 1 January, so comparing the day would
      // read two estimates a year apart as a hard conflict.
      final result = DuplicateDetector.compare(
        patient(id: 'a', given: 'Sita', family: 'Aryal',
            dob: DateTime(1990, 1, 1), estimated: true),
        patient(id: 'b', given: 'Sita', family: 'Aryal',
            dob: DateTime(1990, 6, 14)),
      );
      expect(result.reasons, contains('Same date of birth'));
      expect(result.score, greaterThanOrEqualTo(DuplicateDetector.strongThreshold));
    });
  });

  group('search', () {
    final register = <PatientIdentity>[
      patient(id: '1', given: 'Sita', family: 'Aryal', dob: DateTime(1990, 4, 2)),
      patient(id: '2', given: 'Bikash', family: 'Gurung'),
      patient(id: '3', given: 'Sita', family: 'Aryla', dob: DateTime(1990, 4, 2)),
    ];

    test('returns matches strongest first and excludes the record itself', () {
      final candidate = patient(
        id: '1',
        given: 'Sita',
        family: 'Aryal',
        dob: DateTime(1990, 4, 2),
      );

      final results = DuplicateDetector.search(candidate, register);

      expect(results.map((r) => r.existing.id), isNot(contains('1')));
      expect(results.first.existing.id, '3');
      expect(results.map((r) => r.existing.id), isNot(contains('2')));
    });

    test('an empty register produces no candidates', () {
      expect(
        DuplicateDetector.search(
          patient(given: 'Sita', family: 'Aryal'),
          const <PatientIdentity>[],
        ),
        isEmpty,
      );
    });
  });
}
