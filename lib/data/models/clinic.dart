import '../../core/db/db_types.dart';

enum ClinicType { clinic, hospital, healthPost, pharmacy, homeVisit, telehealth }

extension ClinicTypeX on ClinicType {
  String get label => switch (this) {
        ClinicType.clinic => 'Clinic',
        ClinicType.hospital => 'Hospital',
        ClinicType.healthPost => 'Health post',
        ClinicType.pharmacy => 'Pharmacy',
        ClinicType.homeVisit => 'Home visit',
        ClinicType.telehealth => 'Telehealth',
      };

  static ClinicType parse(String? value) => ClinicType.values
      .where((t) => t.name == value)
      .firstOrNull ?? ClinicType.clinic;
}

/// A site of care. Every encounter is stamped with one, because the same
/// clinician's notes at a hospital and at a rural health post carry different
/// context, formularies and follow-up expectations.
class Clinic {
  const Clinic({
    required this.id,
    required this.name,
    this.code,
    this.type = ClinicType.clinic,
    this.addressLine,
    this.city,
    this.district,
    this.country,
    this.phone,
    this.timezone,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String name;
  final String? code;
  final ClinicType type;
  final String? addressLine;
  final String? city;
  final String? district;
  final String? country;
  final String? phone;
  final String? timezone;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final String syncStatus;

  String get locationLabel =>
      [city, district].where((s) => s != null && s.isNotEmpty).join(', ');

  factory Clinic.fromMap(Map<String, Object?> map) => Clinic(
        id: map['id'] as String,
        name: map['name'] as String,
        code: map['code'] as String?,
        type: ClinicTypeX.parse(map['type'] as String?),
        addressLine: map['address_line'] as String?,
        city: map['city'] as String?,
        district: map['district'] as String?,
        country: map['country'] as String?,
        phone: map['phone'] as String?,
        timezone: map['timezone'] as String?,
        isActive: intToBool(map['is_active']),
        createdAt: fromEpoch(map['created_at'] as int),
        updatedAt: fromEpoch(map['updated_at'] as int),
        deletedAt: fromEpochOrNull(map['deleted_at'] as int?),
        revision: map['revision'] as int? ?? 1,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'code': code,
        'type': type.name,
        'address_line': addressLine,
        'city': city,
        'district': district,
        'country': country,
        'phone': phone,
        'timezone': timezone,
        'is_active': boolToInt(isActive),
        'created_at': toEpoch(createdAt),
        'updated_at': toEpoch(updatedAt),
        'deleted_at': toEpochOrNull(deletedAt),
        'revision': revision,
        'sync_status': syncStatus,
      };

  Clinic copyWith({
    String? name,
    String? code,
    ClinicType? type,
    String? addressLine,
    String? city,
    String? district,
    String? country,
    String? phone,
    bool? isActive,
    DateTime? updatedAt,
  }) =>
      Clinic(
        id: id,
        name: name ?? this.name,
        code: code ?? this.code,
        type: type ?? this.type,
        addressLine: addressLine ?? this.addressLine,
        city: city ?? this.city,
        district: district ?? this.district,
        country: country ?? this.country,
        phone: phone ?? this.phone,
        timezone: timezone,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        deletedAt: deletedAt,
        revision: revision + 1,
        syncStatus: SyncStatus.pending,
      );
}
