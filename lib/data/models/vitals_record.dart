import '../../clinical/calculations.dart';
import '../../clinical/news2.dart';
import '../../clinical/patient_age.dart';
import '../../clinical/vital_reference.dart';
import '../../core/db/db_types.dart';

/// Posture at the time of the reading. Orthostatic changes are real and a
/// standing BP is not comparable with a supine one.
enum MeasurementPosition { sitting, supine, standing }

extension MeasurementPositionX on MeasurementPosition {
  String get label => switch (this) {
        MeasurementPosition.sitting => 'Sitting',
        MeasurementPosition.supine => 'Supine',
        MeasurementPosition.standing => 'Standing',
      };

  static MeasurementPosition? parse(String? value) =>
      MeasurementPosition.values.where((p) => p.name == value).firstOrNull;
}

enum TemperatureSite { oral, axillary, tympanic, temporal, rectal }

extension TemperatureSiteX on TemperatureSite {
  String get label => switch (this) {
        TemperatureSite.oral => 'Oral',
        TemperatureSite.axillary => 'Axillary',
        TemperatureSite.tympanic => 'Tympanic',
        TemperatureSite.temporal => 'Temporal',
        TemperatureSite.rectal => 'Rectal',
      };

  static TemperatureSite? parse(String? value) =>
      TemperatureSite.values.where((s) => s.name == value).firstOrNull;
}

/// A single set of observations.
///
/// [encounterId] is nullable because vitals are routinely taken at triage,
/// before anyone has opened an encounter — forcing an encounter first is the
/// fastest way to make staff record vitals on paper instead.
class VitalsRecord {
  const VitalsRecord({
    required this.id,
    required this.patientId,
    this.encounterId,
    required this.recordedAt,
    this.position,
    this.systolicBp,
    this.diastolicBp,
    this.bpSite,
    this.heartRate,
    this.heartRhythm,
    this.respiratoryRate,
    this.temperatureC,
    this.temperatureSite,
    this.spo2,
    this.onOxygen = false,
    this.oxygenFlowLpm,
    this.oxygenDelivery,
    this.consciousness,
    this.heightCm,
    this.weightKg,
    this.bmi,
    this.headCircumferenceCm,
    this.painScore,
    this.bloodGlucoseMmol,
    this.glucoseTiming,
    this.capillaryRefillSec,
    this.news2Score,
    this.news2Risk,
    this.news2Algorithm,
    this.notes,
    this.recordedBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String patientId;
  final String? encounterId;
  final DateTime recordedAt;
  final MeasurementPosition? position;
  final int? systolicBp;
  final int? diastolicBp;
  final String? bpSite;
  final int? heartRate;
  final String? heartRhythm;
  final int? respiratoryRate;
  final double? temperatureC;
  final TemperatureSite? temperatureSite;
  final int? spo2;
  final bool onOxygen;
  final double? oxygenFlowLpm;
  final String? oxygenDelivery;
  final Consciousness? consciousness;
  final double? heightCm;
  final double? weightKg;

  /// Stored rather than always recomputed so a historic row keeps the value
  /// that was on the chart at the time.
  final double? bmi;
  final double? headCircumferenceCm;
  final int? painScore;
  final double? bloodGlucoseMmol;
  final String? glucoseTiming;
  final double? capillaryRefillSec;

  /// NEWS2 is frozen at capture time along with the algorithm identifier, so
  /// revising the scoring code never silently rewrites past observations.
  final int? news2Score;
  final String? news2Risk;
  final String? news2Algorithm;
  final String? notes;
  final String? recordedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int revision;
  final String syncStatus;

  bool get isEmpty =>
      systolicBp == null &&
      diastolicBp == null &&
      heartRate == null &&
      respiratoryRate == null &&
      temperatureC == null &&
      spo2 == null &&
      heightCm == null &&
      weightKg == null &&
      painScore == null &&
      bloodGlucoseMmol == null;

  String? get bloodPressure =>
      (systolicBp == null || diastolicBp == null) ? null : '$systolicBp/$diastolicBp';

  double? get meanArterialPressure => ClinicalCalc.meanArterialPressure(
        systolic: systolicBp,
        diastolic: diastolicBp,
      );

  /// Per-parameter flags against the patient's age band, used to colour the
  /// values on screen.
  Map<String, VitalFlag> flags(PatientAge? age) => <String, VitalFlag>{
        'systolic': VitalReference.systolic(age).classify(systolicBp),
        'diastolic': VitalReference.diastolic(age).classify(diastolicBp),
        'heartRate': VitalReference.heartRate(age).classify(heartRate),
        'respiratoryRate':
            VitalReference.respiratoryRate(age).classify(respiratoryRate),
        'temperature': VitalReference.temperature.classify(temperatureC),
        'spo2': VitalReference.spo2.classify(spo2),
        'glucose': VitalReference.bloodGlucoseMmol.classify(bloodGlucoseMmol),
        'pain': VitalReference.painScore.classify(painScore),
      };

  bool hasCriticalValue(PatientAge? age) =>
      flags(age).values.any((f) => f.isCritical);

  bool hasAbnormalValue(PatientAge? age) =>
      flags(age).values.any((f) => f.isAbnormal);

  News2Input get news2Input => News2Input(
        respiratoryRate: respiratoryRate,
        spo2: spo2,
        onOxygen: onOxygen,
        systolicBp: systolicBp,
        heartRate: heartRate,
        consciousness: consciousness,
        temperatureC: temperatureC,
      );

  factory VitalsRecord.fromMap(Map<String, Object?> map) => VitalsRecord(
        id: map['id'] as String,
        patientId: map['patient_id'] as String,
        encounterId: map['encounter_id'] as String?,
        recordedAt: fromEpoch(map['recorded_at'] as int),
        position: MeasurementPositionX.parse(map['position'] as String?),
        systolicBp: map['systolic_bp'] as int?,
        diastolicBp: map['diastolic_bp'] as int?,
        bpSite: map['bp_site'] as String?,
        heartRate: map['heart_rate'] as int?,
        heartRhythm: map['heart_rhythm'] as String?,
        respiratoryRate: map['respiratory_rate'] as int?,
        temperatureC: (map['temperature_c'] as num?)?.toDouble(),
        temperatureSite:
            TemperatureSiteX.parse(map['temperature_site'] as String?),
        spo2: map['spo2'] as int?,
        onOxygen: intToBool(map['on_oxygen']),
        oxygenFlowLpm: (map['oxygen_flow_lpm'] as num?)?.toDouble(),
        oxygenDelivery: map['oxygen_delivery'] as String?,
        consciousness: ConsciousnessX.parse(map['consciousness'] as String?),
        heightCm: (map['height_cm'] as num?)?.toDouble(),
        weightKg: (map['weight_kg'] as num?)?.toDouble(),
        bmi: (map['bmi'] as num?)?.toDouble(),
        headCircumferenceCm:
            (map['head_circumference_cm'] as num?)?.toDouble(),
        painScore: map['pain_score'] as int?,
        bloodGlucoseMmol: (map['blood_glucose_mmol'] as num?)?.toDouble(),
        glucoseTiming: map['glucose_timing'] as String?,
        capillaryRefillSec:
            (map['capillary_refill_sec'] as num?)?.toDouble(),
        news2Score: map['news2_score'] as int?,
        news2Risk: map['news2_risk'] as String?,
        news2Algorithm: map['news2_algorithm'] as String?,
        notes: map['notes'] as String?,
        recordedBy: map['recorded_by'] as String?,
        createdAt: fromEpoch(map['created_at'] as int),
        updatedAt: fromEpoch(map['updated_at'] as int),
        deletedAt: fromEpochOrNull(map['deleted_at'] as int?),
        revision: map['revision'] as int? ?? 1,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'patient_id': patientId,
        'encounter_id': encounterId,
        'recorded_at': toEpoch(recordedAt),
        'position': position?.name,
        'systolic_bp': systolicBp,
        'diastolic_bp': diastolicBp,
        'bp_site': bpSite,
        'heart_rate': heartRate,
        'heart_rhythm': heartRhythm,
        'respiratory_rate': respiratoryRate,
        'temperature_c': temperatureC,
        'temperature_site': temperatureSite?.name,
        'spo2': spo2,
        'on_oxygen': boolToInt(onOxygen),
        'oxygen_flow_lpm': oxygenFlowLpm,
        'oxygen_delivery': oxygenDelivery,
        'consciousness': consciousness?.name,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'bmi': bmi,
        'head_circumference_cm': headCircumferenceCm,
        'pain_score': painScore,
        'blood_glucose_mmol': bloodGlucoseMmol,
        'glucose_timing': glucoseTiming,
        'capillary_refill_sec': capillaryRefillSec,
        'news2_score': news2Score,
        'news2_risk': news2Risk,
        'news2_algorithm': news2Algorithm,
        'notes': notes,
        'recorded_by': recordedBy,
        'created_at': toEpoch(createdAt),
        'updated_at': toEpoch(updatedAt),
        'deleted_at': toEpochOrNull(deletedAt),
        'revision': revision,
        'sync_status': syncStatus,
      };
}
