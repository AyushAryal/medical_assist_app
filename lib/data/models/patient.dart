import '../../clinical/patient_age.dart';
import '../../core/db/db_types.dart';

/// Sex recorded at birth. Kept distinct from gender identity because reference
/// ranges, drug dosing and screening pathways key off the former while how a
/// patient is addressed keys off the latter.
enum SexAtBirth { male, female, intersex, unknown }

extension SexAtBirthX on SexAtBirth {
  String get label => switch (this) {
        SexAtBirth.male => 'Male',
        SexAtBirth.female => 'Female',
        SexAtBirth.intersex => 'Intersex',
        SexAtBirth.unknown => 'Unknown',
      };

  String get short => switch (this) {
        SexAtBirth.male => 'M',
        SexAtBirth.female => 'F',
        SexAtBirth.intersex => 'I',
        SexAtBirth.unknown => '—',
      };

  static SexAtBirth parse(String? value) =>
      SexAtBirth.values.where((s) => s.name == value).firstOrNull ??
      SexAtBirth.unknown;
}

/// Three-state on purpose. "Nothing recorded yet" and "asked, and the patient
/// has no known allergies" are clinically different, and collapsing them is
/// how an allergy gets missed.
enum AllergyStatus { unknown, noKnownAllergies, hasAllergies }

extension AllergyStatusX on AllergyStatus {
  String get label => switch (this) {
        AllergyStatus.unknown => 'Allergies not recorded',
        AllergyStatus.noKnownAllergies => 'No known allergies',
        AllergyStatus.hasAllergies => 'Allergies on record',
      };

  static AllergyStatus parse(String? value) =>
      AllergyStatus.values.where((s) => s.name == value).firstOrNull ??
      AllergyStatus.unknown;
}

class Patient {
  const Patient({
    required this.id,
    required this.mrn,
    required this.familyName,
    required this.givenName,
    this.middleName,
    this.preferredName,
    this.sexAtBirth = SexAtBirth.unknown,
    this.genderIdentity,
    this.dateOfBirth,
    this.dobIsEstimated = false,
    this.bloodGroup,
    this.phone,
    this.altPhone,
    this.email,
    this.addressLine,
    this.city,
    this.district,
    this.country,
    this.nationalId,
    this.occupation,
    this.nextOfKinName,
    this.nextOfKinPhone,
    this.nextOfKinRelation,
    this.primaryClinicId,
    this.allergyStatus = AllergyStatus.unknown,
    this.photoPath,
    this.notes,
    this.deceasedDate,
    this.lastSeenAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;

  /// Medical record number. Human-quotable, unique on the device, and the
  /// identifier staff will actually read out over the phone.
  final String mrn;
  final String familyName;
  final String givenName;
  final String? middleName;
  final String? preferredName;
  final SexAtBirth sexAtBirth;
  final String? genderIdentity;
  final DateTime? dateOfBirth;

  /// Set when only an approximate age was available. Surfaced next to the age
  /// so nobody treats an estimate as a verified date.
  final bool dobIsEstimated;
  final String? bloodGroup;
  final String? phone;
  final String? altPhone;
  final String? email;
  final String? addressLine;
  final String? city;
  final String? district;
  final String? country;
  final String? nationalId;
  final String? occupation;
  final String? nextOfKinName;
  final String? nextOfKinPhone;
  final String? nextOfKinRelation;
  final String? primaryClinicId;
  final AllergyStatus allergyStatus;
  final String? photoPath;
  final String? notes;
  final DateTime? deceasedDate;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final String syncStatus;

  String get fullName => '$givenName $familyName';

  String get displayName =>
      preferredName?.isNotEmpty == true ? '$preferredName $familyName' : fullName;

  String get initials {
    final g = givenName.isNotEmpty ? givenName[0] : '';
    final f = familyName.isNotEmpty ? familyName[0] : '';
    return '$g$f'.toUpperCase();
  }

  PatientAge? get age => PatientAge.fromDateOfBirth(dateOfBirth);

  bool get isDeceased => deceasedDate != null;

  /// "34y · F · MRN 000142" — the identity strip shown on every clinical
  /// screen so the clinician always knows whose chart is open.
  String get identityLine {
    final parts = <String>[
      if (age != null) '${dobIsEstimated ? '~' : ''}${age!.label}',
      sexAtBirth.short,
      'MRN $mrn',
    ];
    return parts.join(' · ');
  }

  /// Lowercased haystack for the patient search box, kept denormalised so
  /// lookup stays a single indexed scan even on a large local chart set.
  static String buildSearchIndex({
    required String mrn,
    required String givenName,
    required String familyName,
    String? middleName,
    String? preferredName,
    String? phone,
    String? nationalId,
  }) {
    return <String?>[
      mrn,
      givenName,
      familyName,
      middleName,
      preferredName,
      phone,
      nationalId,
    ].where((s) => s != null && s.isNotEmpty).join(' ').toLowerCase();
  }

  String get searchIndex => buildSearchIndex(
        mrn: mrn,
        givenName: givenName,
        familyName: familyName,
        middleName: middleName,
        preferredName: preferredName,
        phone: phone,
        nationalId: nationalId,
      );

  factory Patient.fromMap(Map<String, Object?> map) => Patient(
        id: map['id'] as String,
        mrn: map['mrn'] as String,
        familyName: map['family_name'] as String,
        givenName: map['given_name'] as String,
        middleName: map['middle_name'] as String?,
        preferredName: map['preferred_name'] as String?,
        sexAtBirth: SexAtBirthX.parse(map['sex_at_birth'] as String?),
        genderIdentity: map['gender_identity'] as String?,
        dateOfBirth: parseIsoDate(map['date_of_birth'] as String?),
        dobIsEstimated: intToBool(map['dob_is_estimated']),
        bloodGroup: map['blood_group'] as String?,
        phone: map['phone'] as String?,
        altPhone: map['alt_phone'] as String?,
        email: map['email'] as String?,
        addressLine: map['address_line'] as String?,
        city: map['city'] as String?,
        district: map['district'] as String?,
        country: map['country'] as String?,
        nationalId: map['national_id'] as String?,
        occupation: map['occupation'] as String?,
        nextOfKinName: map['next_of_kin_name'] as String?,
        nextOfKinPhone: map['next_of_kin_phone'] as String?,
        nextOfKinRelation: map['next_of_kin_rel'] as String?,
        primaryClinicId: map['primary_clinic_id'] as String?,
        allergyStatus: AllergyStatusX.parse(map['allergy_status'] as String?),
        photoPath: map['photo_path'] as String?,
        notes: map['notes'] as String?,
        deceasedDate: parseIsoDate(map['deceased_date'] as String?),
        lastSeenAt: fromEpochOrNull(map['last_seen_at'] as int?),
        createdAt: fromEpoch(map['created_at'] as int),
        updatedAt: fromEpoch(map['updated_at'] as int),
        deletedAt: fromEpochOrNull(map['deleted_at'] as int?),
        revision: map['revision'] as int? ?? 1,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'mrn': mrn,
        'family_name': familyName,
        'given_name': givenName,
        'middle_name': middleName,
        'preferred_name': preferredName,
        'sex_at_birth': sexAtBirth.name,
        'gender_identity': genderIdentity,
        'date_of_birth': toIsoDateOrNull(dateOfBirth),
        'dob_is_estimated': boolToInt(dobIsEstimated),
        'blood_group': bloodGroup,
        'phone': phone,
        'alt_phone': altPhone,
        'email': email,
        'address_line': addressLine,
        'city': city,
        'district': district,
        'country': country,
        'national_id': nationalId,
        'occupation': occupation,
        'next_of_kin_name': nextOfKinName,
        'next_of_kin_phone': nextOfKinPhone,
        'next_of_kin_rel': nextOfKinRelation,
        'primary_clinic_id': primaryClinicId,
        'allergy_status': allergyStatus.name,
        'photo_path': photoPath,
        'notes': notes,
        'deceased_date': toIsoDateOrNull(deceasedDate),
        'search_index': searchIndex,
        'last_seen_at': toEpochOrNull(lastSeenAt),
        'created_at': toEpoch(createdAt),
        'updated_at': toEpoch(updatedAt),
        'deleted_at': toEpochOrNull(deletedAt),
        'revision': revision,
        'sync_status': syncStatus,
      };

  Patient copyWith({
    String? mrn,
    String? familyName,
    String? givenName,
    String? middleName,
    String? preferredName,
    SexAtBirth? sexAtBirth,
    String? genderIdentity,
    DateTime? dateOfBirth,
    bool? dobIsEstimated,
    String? bloodGroup,
    String? phone,
    String? altPhone,
    String? email,
    String? addressLine,
    String? city,
    String? district,
    String? country,
    String? nationalId,
    String? occupation,
    String? nextOfKinName,
    String? nextOfKinPhone,
    String? nextOfKinRelation,
    String? primaryClinicId,
    AllergyStatus? allergyStatus,
    String? photoPath,
    String? notes,
    DateTime? deceasedDate,
    DateTime? lastSeenAt,
    DateTime? deletedAt,
  }) =>
      Patient(
        id: id,
        mrn: mrn ?? this.mrn,
        familyName: familyName ?? this.familyName,
        givenName: givenName ?? this.givenName,
        middleName: middleName ?? this.middleName,
        preferredName: preferredName ?? this.preferredName,
        sexAtBirth: sexAtBirth ?? this.sexAtBirth,
        genderIdentity: genderIdentity ?? this.genderIdentity,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        dobIsEstimated: dobIsEstimated ?? this.dobIsEstimated,
        bloodGroup: bloodGroup ?? this.bloodGroup,
        phone: phone ?? this.phone,
        altPhone: altPhone ?? this.altPhone,
        email: email ?? this.email,
        addressLine: addressLine ?? this.addressLine,
        city: city ?? this.city,
        district: district ?? this.district,
        country: country ?? this.country,
        nationalId: nationalId ?? this.nationalId,
        occupation: occupation ?? this.occupation,
        nextOfKinName: nextOfKinName ?? this.nextOfKinName,
        nextOfKinPhone: nextOfKinPhone ?? this.nextOfKinPhone,
        nextOfKinRelation: nextOfKinRelation ?? this.nextOfKinRelation,
        primaryClinicId: primaryClinicId ?? this.primaryClinicId,
        allergyStatus: allergyStatus ?? this.allergyStatus,
        photoPath: photoPath ?? this.photoPath,
        notes: notes ?? this.notes,
        deceasedDate: deceasedDate ?? this.deceasedDate,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt ?? this.deletedAt,
        revision: revision + 1,
        syncStatus: SyncStatus.pending,
      );
}
