import 'package:flutter/foundation.dart';

import '../../core/utils/ids.dart';
import '../models/allergy.dart';
import '../models/appointment.dart';
import '../models/encounter.dart';
import '../models/medication.dart';
import '../models/patient.dart';
import '../models/problem.dart';
import '../models/vitals_record.dart';
import '../repositories/clinical_repository.dart';
import '../../clinical/news2.dart';

/// Whether demo-data seeding is available in this build at all.
///
/// Debug builds always allow it. A release build allows it only when it was
/// compiled with `--dart-define=ALLOW_DEMO_DATA=true` — the one switch that
/// turns an ordinary release into a reviewer/demo build for putting realistic
/// content on a real device. A shipped clinical build passes neither, so the
/// settings section is compiled out and [DemoDataSeeder.seed] refuses to run,
/// exactly as before: this widens the old debug-only guard by a single
/// explicit, build-time opt-in and nothing else. There is no runtime toggle,
/// so a fabricated patient can never appear in a build that was not deliberately
/// made to hold one.
const bool demoDataAllowed =
    kDebugMode || bool.fromEnvironment('ALLOW_DEMO_DATA');

/// Seeds a realistic demo dataset for development and demonstration.
///
/// Three safety rules govern this file, because fabricated patients inside a
/// clinical record system are genuinely dangerous:
///
/// 1. **Opt-in builds only.** [seed] refuses unless [demoDataAllowed] — a debug
///    build, or a release compiled with `--dart-define=ALLOW_DEMO_DATA=true`.
/// 2. **Every record is marked.** Demo patients carry [marker] in their notes
///    and a `(DEMO)` name suffix, so they are unmistakable in a patient list
///    and cannot be quietly confused with a real chart.
/// 3. **Reversible.** [clear] removes exactly what [seed] created, matched on
///    the marker, and nothing else.
///
/// The dataset is chosen to exercise the parts of the app that are hard to
/// review empty: age-banded vital flagging across neonate → elderly, an
/// anaphylactic allergy that drives the red banner, an unsigned charting
/// backlog, a signed-and-amended note, and two patients whose observations
/// today score high enough on NEWS2 to reach the dashboard.
class DemoDataSeeder {
  const DemoDataSeeder(this._repository);

  final ClinicalRepository _repository;

  /// Sentinel written into `patients.notes`. Used to find and remove demo rows.
  static const String marker = '[DEMO]';

  static const String _nameSuffix = '(DEMO)';

  Future<int> count() async {
    final patients = await _repository.patients.recent(limit: 500);
    return patients.where(_isDemo).length;
  }

  static bool _isDemo(Patient patient) =>
      patient.notes?.startsWith(marker) ?? false;

  /// Creates the dataset. Returns the number of patients added.
  Future<int> seed() async {
    if (!demoDataAllowed) {
      throw StateError(
        'Demo data cannot be seeded into a shipped build. Rebuild with '
        '--dart-define=ALLOW_DEMO_DATA=true to enable it.',
      );
    }

    final clinic = await _repository.ensureDefaultClinic();
    final now = DateTime.now();
    var created = 0;

    for (final spec in _specs(now)) {
      final patient = await _repository.createPatient(
        Patient(
          id: newId(),
          mrn: '',
          givenName: spec.givenName,
          familyName: '${spec.familyName} $_nameSuffix',
          sexAtBirth: spec.sex,
          dateOfBirth: spec.dateOfBirth,
          dobIsEstimated: spec.dobIsEstimated,
          phone: spec.phone,
          city: spec.city,
          allergyStatus: spec.allergies.isEmpty
              ? AllergyStatus.noKnownAllergies
              : AllergyStatus.hasAllergies,
          primaryClinicId: clinic.id,
          notes: '$marker Fictional record for demonstration only.',
          createdAt: now,
          updatedAt: now,
        ),
      );
      created++;

      for (final allergy in spec.allergies) {
        await _repository.patients.addAllergy(
          Allergy(
            id: newId(),
            patientId: patient.id,
            substance: allergy.substance,
            category: allergy.category,
            reaction: allergy.reaction,
            severity: allergy.severity,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      for (final problem in spec.problems) {
        await _repository.patients.addProblem(
          Problem(
            id: newId(),
            patientId: patient.id,
            display: problem.display,
            codeSystem: problem.code == null ? null : 'ICD-10',
            code: problem.code,
            isChronic: problem.isChronic,
            onsetDate: now.subtract(Duration(days: problem.onsetDaysAgo)),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      for (final medication in spec.medications) {
        await _repository.patients.addMedication(
          Medication(
            id: newId(),
            patientId: patient.id,
            name: medication.name,
            dose: medication.dose,
            route: medication.route,
            frequency: medication.frequency,
            indication: medication.indication,
            startedOn: now.subtract(Duration(days: medication.startedDaysAgo)),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      await _seedVisits(patient: patient, spec: spec, clinicId: clinic.id);
      await _seedAppointments(
        patient: patient,
        spec: spec,
        clinicId: clinic.id,
      );
    }

    return created;
  }

  Future<void> _seedVisits({
    required Patient patient,
    required _PatientSpec spec,
    required String clinicId,
  }) async {
    final ageYears = patient.age?.years;

    for (final visit in spec.visits) {
      final startedAt = DateTime.now().subtract(
        Duration(hours: visit.hoursAgo),
      );

      final encounter = await _repository.startEncounter(
        patientId: patient.id,
        clinicId: clinicId,
        type: visit.type,
        chiefComplaint: visit.chiefComplaint,
        providerName: visit.providerName,
        startedAt: startedAt,
      );

      if (visit.vitals != null) {
        final v = visit.vitals!;
        await _repository.recordVitals(
          draft: VitalsRecord(
            id: newId(),
            patientId: patient.id,
            encounterId: encounter.id,
            recordedAt: startedAt.add(const Duration(minutes: 4)),
            position: MeasurementPosition.sitting,
            systolicBp: v.systolic,
            diastolicBp: v.diastolic,
            heartRate: v.heartRate,
            respiratoryRate: v.respiratoryRate,
            temperatureC: v.temperature,
            temperatureSite: TemperatureSite.oral,
            spo2: v.spo2,
            onOxygen: v.onOxygen,
            oxygenFlowLpm: v.onOxygen ? 2 : null,
            consciousness: v.consciousness,
            heightCm: v.heightCm,
            weightKg: v.weightKg,
            painScore: v.painScore,
            recordedBy: visit.providerName,
            createdAt: startedAt,
            updatedAt: startedAt,
          ),
          patientAgeYears: ageYears,
        );
      }

      if (visit.note != null) {
        final draft = await _repository.noteForEncounter(encounter);
        final filled = draft.copyWith(
          subjective: visit.note!.subjective,
          objective: visit.note!.objective,
          assessment: visit.note!.assessment,
          plan: visit.note!.plan,
        );
        await _repository.saveNoteDraft(filled);

        if (visit.signed) {
          final signed = await _repository.signNote(
            filled,
            signedBy: visit.providerName,
          );
          await _repository.signEncounter(
            encounter: encounter.copyWith(
              endedAt: startedAt.add(const Duration(minutes: 20)),
              disposition: visit.disposition,
              followUpDate: visit.followUpInDays == null
                  ? null
                  : DateTime.now().add(Duration(days: visit.followUpInDays!)),
            ),
            signedBy: visit.providerName,
          );

          if (visit.amendment != null) {
            await _repository.amendNote(
              note: signed,
              body: visit.amendment!,
              reason: 'Result received after signing',
              author: visit.providerName,
            );
          }
        }
      }
    }
  }

  /// Books today's clinic list so the schedule and dashboard have content.
  Future<void> _seedAppointments({
    required Patient patient,
    required _PatientSpec spec,
    required String clinicId,
  }) async {
    final now = DateTime.now();

    for (final slot in spec.appointments) {
      final scheduledAt = DateTime(
        now.year,
        now.month,
        now.day,
        slot.hour,
        slot.minute,
      ).add(Duration(days: slot.dayOffset));

      final appointment = await _repository.bookAppointment(
        patientId: patient.id,
        clinicId: clinicId,
        scheduledAt: scheduledAt,
        durationMinutes: slot.durationMinutes,
        type: slot.type,
        reason: slot.reason,
        providerName: 'Dr A. Sharma',
      );

      switch (slot.status) {
        case AppointmentStatus.arrived:
          await _repository.markArrived(appointment);
        case AppointmentStatus.completed:
        case AppointmentStatus.noShow:
        case AppointmentStatus.cancelled:
          await _repository.closeAppointment(appointment, slot.status);
        default:
          break;
      }
    }
  }

  /// Removes every record created by [seed]. Returns the patients removed.
  Future<int> clear() async {
    final patients = await _repository.patients.recent(limit: 500);
    final demo = patients.where(_isDemo).toList();

    for (final patient in demo) {
      for (final appointment
          in await _repository.appointments.forPatient(patient.id)) {
        await _repository.appointments.archive(appointment.id);
      }
      for (final encounter in await _repository.encounters.forPatient(patient.id)) {
        await _repository.encounters.update(
          encounter.copyWith(deletedAt: DateTime.now()),
        );
      }
      for (final record in await _repository.vitals.forPatient(patient.id)) {
        await _repository.vitals.archive(record.id);
      }
      await _repository.patients.archive(patient.id);
    }
    return demo.length;
  }

  // ---------------------------------------------------------------- dataset

  static List<_PatientSpec> _specs(DateTime now) {
    DateTime yearsAgo(int years, [int month = 6, int day = 12]) =>
        DateTime(now.year - years, month, day);

    return <_PatientSpec>[
      // Elderly, deteriorating: drives the dashboard "needs a second look".
      _PatientSpec(
        givenName: 'Bimala',
        familyName: 'Shrestha',
        sex: SexAtBirth.female,
        dateOfBirth: yearsAgo(74, 3, 2),
        phone: '9801110001',
        city: 'Lalitpur',
        allergies: const [
          _AllergySpec(
            substance: 'Penicillin',
            reaction: 'Facial swelling, difficulty breathing',
            severity: AllergySeverity.anaphylaxis,
          ),
        ],
        problems: const [
          _ProblemSpec('Type 2 diabetes mellitus', 'E11.9', true, 2200),
          _ProblemSpec('Essential hypertension', 'I10', true, 3100),
          _ProblemSpec('Chronic kidney disease, stage 3', 'N18.3', true, 700),
        ],
        medications: const [
          _MedicationSpec('Metformin', '500 mg', 'PO', 'BD', 'Type 2 diabetes', 2100),
          _MedicationSpec('Amlodipine', '5 mg', 'PO', 'OD', 'Hypertension', 1400),
        ],
        appointments: const [
          _SlotSpec(
            hour: 9,
            durationMinutes: 30,
            type: EncounterType.emergency,
            reason: 'Fever and confusion',
            status: AppointmentStatus.completed,
          ),
          _SlotSpec(
            hour: 11,
            dayOffset: 3,
            durationMinutes: 20,
            reason: 'Sepsis follow-up and renal review',
          ),
        ],
        visits: [
          _VisitSpec(
            hoursAgo: 2,
            type: EncounterType.emergency,
            chiefComplaint: 'Fever and confusion since yesterday',
            providerName: 'Dr A. Sharma',
            // RR 24 (+2), SpO2 92 (+2), on O2 (+2), SBP 98 (+2),
            // HR 118 (+2), alert (0), 38.6 C (+1) = 11 → high risk.
            vitals: const _VitalsSpec(
              systolic: 98,
              diastolic: 58,
              heartRate: 118,
              respiratoryRate: 24,
              temperature: 38.6,
              spo2: 92,
              onOxygen: true,
              consciousness: Consciousness.alert,
              weightKg: 58,
              heightCm: 151,
              painScore: 3,
            ),
            note: _NoteSpec(
              subjective: 'Daughter reports two days of fever, reduced oral '
                  'intake and new confusion this morning. Dysuria for four '
                  'days. No cough or breathlessness.',
              objective: 'Unwell, warm peripheries. Chest clear. Abdomen soft '
                  'with suprapubic tenderness. No rash or neck stiffness.',
              assessment: 'Urosepsis in a patient with CKD 3 and diabetes. '
                  'NEWS2 11 — high risk, needs urgent senior review.',
              plan: 'IV access, blood cultures before antibiotics. Avoid '
                  'penicillins (anaphylaxis). Start IV gentamicin per local '
                  'protocol with renal dosing. Hourly observations. Discussed '
                  'with medical registrar for admission.',
            ),
          ),
        ],
      ),

      // Adult with an unsigned draft — the charting backlog.
      _PatientSpec(
        givenName: 'Rajesh',
        familyName: 'Thapa',
        sex: SexAtBirth.male,
        dateOfBirth: yearsAgo(41, 11, 20),
        phone: '9801110002',
        city: 'Kathmandu',
        problems: const [
          _ProblemSpec('Gastro-oesophageal reflux disease', 'K21.9', false, 400),
        ],
        medications: const [
          _MedicationSpec('Omeprazole', '20 mg', 'PO', 'OD', 'Reflux', 380),
        ],
        appointments: const [
          _SlotSpec(
            hour: 14,
            minute: 30,
            reason: 'Reflux review',
            status: AppointmentStatus.arrived,
          ),
        ],
        visits: [
          _VisitSpec(
            hoursAgo: 5,
            type: EncounterType.followUp,
            chiefComplaint: 'Burning chest pain after meals',
            providerName: 'Dr A. Sharma',
            vitals: const _VitalsSpec(
              systolic: 128,
              diastolic: 82,
              heartRate: 76,
              respiratoryRate: 16,
              temperature: 36.8,
              spo2: 98,
              consciousness: Consciousness.alert,
              weightKg: 82,
              heightCm: 172,
              painScore: 4,
            ),
            note: _NoteSpec(
              subjective: 'Retrosternal burning after evening meals, worse '
                  'lying flat. No exertional component, no radiation to the '
                  'jaw or arm. Taking omeprazole irregularly.',
              objective: 'Comfortable at rest. Chest clear, heart sounds '
                  'normal. Abdomen soft, mild epigastric tenderness.',
              assessment: '',
              plan: '',
            ),
            // Left unsigned on purpose.
            signed: false,
          ),
        ],
      ),

      // Moderate NEWS2 today — the medium-risk row.
      _PatientSpec(
        givenName: 'Sunita',
        familyName: 'Gurung',
        sex: SexAtBirth.female,
        dateOfBirth: yearsAgo(33, 8, 4),
        phone: '9801110003',
        city: 'Pokhara',
        problems: const [
          _ProblemSpec('Asthma', 'J45.909', true, 5000),
        ],
        medications: const [
          _MedicationSpec('Salbutamol inhaler', '100 mcg', 'INH', 'PRN', 'Asthma', 900),
        ],
        appointments: const [
          _SlotSpec(
            hour: 15,
            durationMinutes: 20,
            type: EncounterType.emergency,
            reason: 'Asthma review after exacerbation',
          ),
        ],
        visits: [
          _VisitSpec(
            hoursAgo: 3,
            type: EncounterType.emergency,
            chiefComplaint: 'Wheeze and shortness of breath',
            providerName: 'Dr A. Sharma',
            // RR 21 (+2), SpO2 94 (+1), SBP 105 (+1), HR 95 (+1),
            // 38.2 C (+1) = 6 → medium risk.
            vitals: const _VitalsSpec(
              systolic: 105,
              diastolic: 68,
              heartRate: 95,
              respiratoryRate: 21,
              temperature: 38.2,
              spo2: 94,
              consciousness: Consciousness.alert,
              weightKg: 54,
              heightCm: 158,
              painScore: 0,
            ),
            note: _NoteSpec(
              subjective: 'Two days of coryza, now wheezy with cough. Using '
                  'salbutamol four-hourly with partial relief. Able to speak '
                  'in full sentences.',
              objective: 'Widespread expiratory wheeze. No accessory muscle '
                  'use. Speaking full sentences.',
              assessment: 'Moderate asthma exacerbation with an intercurrent '
                  'viral illness. NEWS2 6 — urgent clinician review.',
              plan: 'Salbutamol via spacer, reassess in 20 minutes. '
                  'Prednisolone 40 mg daily for five days. Written asthma '
                  'action plan given. Return immediately if speech becomes '
                  'difficult.',
            ),
          ),
        ],
      ),

      // Infant — exercises paediatric reference bands (HR 140 is normal here).
      _PatientSpec(
        givenName: 'Aarav',
        familyName: 'Karki',
        sex: SexAtBirth.male,
        dateOfBirth: DateTime(now.year, now.month - 7, 15),
        phone: '9801110004',
        city: 'Bhaktapur',
        appointments: const [
          _SlotSpec(
            hour: 10,
            minute: 15,
            type: EncounterType.immunisation,
            reason: 'Eight-week immunisation and growth check',
            dayOffset: 1,
          ),
        ],
        visits: [
          _VisitSpec(
            hoursAgo: 26,
            type: EncounterType.immunisation,
            chiefComplaint: 'Routine immunisation and growth check',
            providerName: 'Dr A. Sharma',
            vitals: const _VitalsSpec(
              heartRate: 140,
              respiratoryRate: 34,
              temperature: 36.9,
              spo2: 98,
              consciousness: Consciousness.alert,
              weightKg: 8.1,
              heightCm: 69,
            ),
            note: _NoteSpec(
              subjective: 'Well baby. Feeding well, six wet nappies daily. '
                  'Mother has no concerns.',
              objective: 'Alert and interactive. Weight and length tracking '
                  'along the expected centile. Heart and chest normal.',
              assessment: 'Thriving infant. Vital signs normal for age — note '
                  'a pulse of 140 is expected at seven months.',
              plan: 'Immunisations given as scheduled. Next review in eight '
                  'weeks. Safety-netting for fever discussed.',
            ),
            signed: true,
            disposition: Disposition.home,
            followUpInDays: 56,
          ),
        ],
      ),

      // Signed and later amended — demonstrates the amendment chain.
      _PatientSpec(
        givenName: 'Kamala',
        familyName: 'Adhikari',
        sex: SexAtBirth.female,
        dateOfBirth: yearsAgo(58, 1, 9),
        phone: '9801110005',
        city: 'Kathmandu',
        allergies: const [
          _AllergySpec(
            substance: 'Sulfonamides',
            reaction: 'Widespread rash',
            severity: AllergySeverity.moderate,
          ),
        ],
        problems: const [
          _ProblemSpec('Hypothyroidism', 'E03.9', true, 1800),
        ],
        medications: const [
          _MedicationSpec('Levothyroxine', '75 mcg', 'PO', 'Mane', 'Hypothyroidism', 1700),
        ],
        appointments: const [
          _SlotSpec(
            hour: 16,
            reason: 'Thyroid function recheck',
          ),
          _SlotSpec(
            hour: 9,
            minute: 30,
            dayOffset: -2,
            reason: 'Missed blood test appointment',
            status: AppointmentStatus.noShow,
          ),
        ],
        visits: [
          _VisitSpec(
            hoursAgo: 52,
            type: EncounterType.followUp,
            chiefComplaint: 'Tiredness, review of thyroid function',
            providerName: 'Dr A. Sharma',
            vitals: const _VitalsSpec(
              systolic: 134,
              diastolic: 84,
              heartRate: 64,
              respiratoryRate: 15,
              temperature: 36.4,
              spo2: 97,
              consciousness: Consciousness.alert,
              weightKg: 71,
              heightCm: 156,
              painScore: 1,
            ),
            note: _NoteSpec(
              subjective: 'Persistent tiredness over three months despite '
                  'adherence to levothyroxine. No cold intolerance or weight '
                  'change.',
              objective: 'Euthyroid clinically. No goitre. Pulse 64 regular.',
              assessment: 'Fatigue on stable levothyroxine. Awaiting TFTs.',
              plan: 'TFTs and full blood count sent. Continue current dose '
                  'pending results. Review in two weeks.',
            ),
            signed: true,
            disposition: Disposition.home,
            followUpInDays: 14,
            amendment: 'TSH 6.8 mIU/L (raised), free T4 low-normal. '
                'Levothyroxine increased to 100 mcg daily. Patient telephoned '
                'and informed; repeat TFTs in six weeks.',
          ),
        ],
      ),

      // Estimated date of birth — shows the "~" age treatment.
      _PatientSpec(
        givenName: 'Hari',
        familyName: 'Bahadur',
        sex: SexAtBirth.male,
        dateOfBirth: DateTime(now.year - 67, 1, 1),
        dobIsEstimated: true,
        phone: '9801110006',
        city: 'Chitwan',
        problems: const [
          _ProblemSpec('Osteoarthritis of the knee', 'M17.9', true, 1200),
        ],
        appointments: const [
          _SlotSpec(
            hour: 16,
            minute: 30,
            durationMinutes: 20,
            reason: 'Knee review and repeat BP',
          ),
        ],
        visits: [
          _VisitSpec(
            hoursAgo: 96,
            type: EncounterType.newPatient,
            chiefComplaint: 'Knee pain on walking',
            providerName: 'Dr A. Sharma',
            vitals: const _VitalsSpec(
              systolic: 142,
              diastolic: 88,
              heartRate: 78,
              respiratoryRate: 17,
              temperature: 36.6,
              spo2: 96,
              consciousness: Consciousness.alert,
              weightKg: 66,
              heightCm: 163,
              painScore: 6,
            ),
            note: _NoteSpec(
              subjective: 'Right knee pain for two years, worse on stairs and '
                  'after walking to the field. Exact age unknown; date of '
                  'birth recorded as an estimate.',
              objective: 'Reduced flexion, crepitus, no effusion or erythema.',
              assessment: 'Osteoarthritis of the right knee. Blood pressure '
                  'raised on a single reading — not diagnostic alone.',
              plan: 'Paracetamol regularly, quadriceps exercises. Repeat BP on '
                  'two further occasions before considering treatment.',
            ),
            signed: true,
            disposition: Disposition.home,
            followUpInDays: 30,
          ),
        ],
      ),
    ];
  }
}

// ------------------------------------------------------------ spec records

class _PatientSpec {
  const _PatientSpec({
    required this.givenName,
    required this.familyName,
    required this.sex,
    required this.dateOfBirth,
    this.dobIsEstimated = false,
    this.phone,
    this.city,
    this.allergies = const [],
    this.problems = const [],
    this.medications = const [],
    this.visits = const [],
    this.appointments = const [],
  });

  final String givenName;
  final String familyName;
  final SexAtBirth sex;
  final DateTime dateOfBirth;
  final bool dobIsEstimated;
  final String? phone;
  final String? city;
  final List<_AllergySpec> allergies;
  final List<_ProblemSpec> problems;
  final List<_MedicationSpec> medications;
  final List<_VisitSpec> visits;
  final List<_SlotSpec> appointments;
}

class _SlotSpec {
  const _SlotSpec({
    required this.hour,
    this.minute = 0,
    this.dayOffset = 0,
    this.durationMinutes = 15,
    this.type = EncounterType.followUp,
    this.reason,
    this.status = AppointmentStatus.scheduled,
  });

  final int hour;
  final int minute;
  final int dayOffset;
  final int durationMinutes;
  final EncounterType type;
  final String? reason;
  final AppointmentStatus status;
}

class _AllergySpec {
  const _AllergySpec({
    required this.substance,
    required this.reaction,
    required this.severity,
  });

  final String substance;
  final String reaction;
  final AllergySeverity severity;

  /// Every demo allergy is a drug allergy — that is the category that drives
  /// the prescribing banner, which is the behaviour worth demonstrating.
  AllergyCategory get category => AllergyCategory.drug;
}

class _ProblemSpec {
  const _ProblemSpec(this.display, this.code, this.isChronic, this.onsetDaysAgo);

  final String display;
  final String? code;
  final bool isChronic;
  final int onsetDaysAgo;
}

class _MedicationSpec {
  const _MedicationSpec(
    this.name,
    this.dose,
    this.route,
    this.frequency,
    this.indication,
    this.startedDaysAgo,
  );

  final String name;
  final String dose;
  final String route;
  final String frequency;
  final String indication;
  final int startedDaysAgo;
}

class _VisitSpec {
  const _VisitSpec({
    required this.hoursAgo,
    required this.type,
    required this.chiefComplaint,
    required this.providerName,
    this.vitals,
    this.note,
    this.signed = true,
    this.disposition,
    this.followUpInDays,
    this.amendment,
  });

  final int hoursAgo;
  final EncounterType type;
  final String chiefComplaint;
  final String providerName;
  final _VitalsSpec? vitals;
  final _NoteSpec? note;
  final bool signed;
  final Disposition? disposition;
  final int? followUpInDays;
  final String? amendment;
}

class _VitalsSpec {
  const _VitalsSpec({
    this.systolic,
    this.diastolic,
    this.heartRate,
    this.respiratoryRate,
    this.temperature,
    this.spo2,
    this.onOxygen = false,
    this.consciousness,
    this.heightCm,
    this.weightKg,
    this.painScore,
  });

  final int? systolic;
  final int? diastolic;
  final int? heartRate;
  final int? respiratoryRate;
  final double? temperature;
  final int? spo2;
  final bool onOxygen;
  final Consciousness? consciousness;
  final double? heightCm;
  final double? weightKg;
  final int? painScore;
}

class _NoteSpec {
  const _NoteSpec({
    required this.subjective,
    required this.objective,
    required this.assessment,
    required this.plan,
  });

  final String subjective;
  final String objective;
  final String assessment;
  final String plan;
}
