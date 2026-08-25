import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/data/models/patient.dart';

void main() {
  Patient patient({
    String given = 'Asha',
    String family = 'Rana',
    String? preferred,
    String? phone,
    DateTime? dob,
    bool estimated = false,
    AllergyStatus allergies = AllergyStatus.unknown,
  }) {
    return Patient(
      id: 'p1',
      mrn: '000142',
      givenName: given,
      familyName: family,
      preferredName: preferred,
      sexAtBirth: SexAtBirth.female,
      dateOfBirth: dob ?? DateTime(1992, 3, 4),
      dobIsEstimated: estimated,
      phone: phone,
      allergyStatus: allergies,
      createdAt: DateTime(2026, 6, 15),
      updatedAt: DateTime(2026, 6, 15),
    );
  }

  group('naming', () {
    test('prefers the preferred name when one is set', () {
      expect(patient().displayName, 'Asha Rana');
      expect(patient(preferred: 'Ash').displayName, 'Ash Rana');
      expect(patient(preferred: 'Ash').fullName, 'Asha Rana');
    });

    test('builds initials from the legal name', () {
      expect(patient().initials, 'AR');
    });
  });

  group('identity line', () {
    test('carries age, sex and MRN', () {
      expect(patient().identityLine, contains('MRN 000142'));
      expect(patient().identityLine, contains('F'));
    });

    test('marks an estimated date of birth with a tilde', () {
      expect(patient(estimated: true).identityLine, startsWith('~'));
      expect(patient().identityLine, isNot(startsWith('~')));
    });
  });

  group('search index', () {
    test('includes every field a user might search by', () {
      final index = patient(phone: '9801234567').searchIndex;
      expect(index, contains('000142'));
      expect(index, contains('asha'));
      expect(index, contains('rana'));
      expect(index, contains('9801234567'));
    });

    test('is lowercased so matching is case-insensitive', () {
      expect(patient(given: 'ASHA').searchIndex, contains('asha'));
    });
  });

  group('round trip', () {
    test('survives toMap/fromMap unchanged', () {
      final original = patient(
        phone: '9801234567',
        allergies: AllergyStatus.noKnownAllergies,
      );
      final restored = Patient.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.mrn, original.mrn);
      expect(restored.givenName, original.givenName);
      expect(restored.sexAtBirth, original.sexAtBirth);
      expect(restored.dateOfBirth, original.dateOfBirth);
      expect(restored.allergyStatus, AllergyStatus.noKnownAllergies);
      expect(restored.phone, original.phone);
    });

    test('stores the date of birth as a timezone-proof calendar date', () {
      final map = patient(dob: DateTime(1992, 3, 4)).toMap();
      expect(map['date_of_birth'], '1992-03-04');
    });

    test('unknown enum values fall back rather than throwing', () {
      final map = patient().toMap()..['sex_at_birth'] = 'not-a-value';
      expect(Patient.fromMap(map).sexAtBirth, SexAtBirth.unknown);
    });
  });

  test('allergy status distinguishes "not asked" from "none"', () {
    expect(AllergyStatus.unknown.label, 'Allergies not recorded');
    expect(AllergyStatus.noKnownAllergies.label, 'No known allergies');
    expect(
      AllergyStatus.unknown,
      isNot(AllergyStatus.noKnownAllergies),
    );
  });
}
