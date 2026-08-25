import 'data_field.dart';

/// The nine tables, described the way people ask about them.
///
/// This file is *data*: names, synonyms, units, kinds, derivations. The
/// matching logic lives in `field_registry.dart` and the types in
/// `data_field.dart`, so a clinician-facing change — a new synonym, a new
/// derived field, a corrected unit — is a one-file edit that touches no
/// behaviour, and a reviewer can read the whole vocabulary top to bottom
/// without stepping over algorithms.
abstract final class ClinicalTables {
  static const DataField age = DataField(
    name: 'age',
    label: 'Age',
    kind: FieldKind.numeric,
    unit: 'years',
    synonyms: <String>['age', 'years old', 'age in years'],
    sources: <String>['date_of_birth'],
    derive: _ageFromDob,
  );

  static Object? _ageFromDob(Map<String, Object?> row) {
    final raw = row['date_of_birth'];
    if (raw is! String || raw.length < 4) return null;
    final born = DateTime.tryParse(raw);
    if (born == null) return null;
    final now = DateTime.now();
    var years = now.year - born.year;
    if (now.month < born.month ||
        (now.month == born.month && now.day < born.day)) {
      years--;
    }
    return years < 0 || years > 130 ? null : years;
  }

  static final DataTable patients = DataTable(
    name: 'patients',
    label: 'patients',
    singular: 'patient',
    synonyms: const <String>['patient', 'people', 'person', 'register',
        'cohort', 'population', 'caseload'],
    timeField: 'created_at',
    fields: <DataField>[
      age,
      const DataField(
        name: 'sex_at_birth',
        label: 'Sex at birth',
        kind: FieldKind.categorical,
        synonyms: <String>['sex', 'gender', 'sex at birth', 'male female'],
      ),
      const DataField(
        name: 'blood_group',
        label: 'Blood group',
        kind: FieldKind.categorical,
        synonyms: <String>['blood group', 'blood type', 'blood'],
      ),
      const DataField(
        name: 'city',
        label: 'City',
        kind: FieldKind.categorical,
        synonyms: <String>['city', 'town'],
      ),
      const DataField(
        name: 'district',
        label: 'District',
        kind: FieldKind.categorical,
        synonyms: <String>['district', 'region', 'area', 'ward'],
      ),
      const DataField(
        name: 'country',
        label: 'Country',
        kind: FieldKind.categorical,
        synonyms: <String>['country', 'nationality'],
      ),
      const DataField(
        name: 'occupation',
        label: 'Occupation',
        kind: FieldKind.categorical,
        synonyms: <String>['occupation', 'job', 'work', 'profession'],
      ),
      const DataField(
        name: 'allergy_status',
        label: 'Allergy status',
        kind: FieldKind.categorical,
        synonyms: <String>['allergy status', 'allergies recorded'],
      ),
      const DataField(
        name: 'created_at',
        label: 'Registered',
        kind: FieldKind.temporal,
        synonyms: <String>['registered', 'registration', 'joined', 'enrolled',
            'added'],
      ),
      const DataField(
        name: 'last_seen_at',
        label: 'Last seen',
        kind: FieldKind.temporal,
        synonyms: <String>['last seen', 'last visit', 'last attended'],
      ),
      const DataField(
        name: 'date_of_birth',
        label: 'Date of birth',
        kind: FieldKind.temporal,
        synonyms: <String>['date of birth', 'birthday', 'dob', 'born'],
      ),
      const DataField(
        name: 'mrn',
        label: 'MRN',
        kind: FieldKind.identifier,
        synonyms: <String>['mrn', 'medical record number', 'record number',
            'chart number'],
      ),
      const DataField(
        name: 'phone',
        label: 'Phone',
        kind: FieldKind.identifier,
        synonyms: <String>['phone', 'phone number', 'contact number',
            'contact', 'mobile', 'telephone', 'number'],
      ),
      const DataField(
        name: 'email',
        label: 'Email',
        kind: FieldKind.identifier,
        synonyms: <String>['email', 'email address', 'mail'],
      ),
      const DataField(
        name: 'address_line',
        label: 'Address',
        kind: FieldKind.identifier,
        synonyms: <String>['address', 'street address', 'where they live'],
      ),
      const DataField(
        name: 'next_of_kin_name',
        label: 'Next of kin',
        kind: FieldKind.identifier,
        synonyms: <String>['next of kin', 'kin', 'emergency contact'],
      ),
      const DataField(
        name: 'next_of_kin_phone',
        label: 'Next of kin phone',
        kind: FieldKind.identifier,
        synonyms: <String>['next of kin phone', 'kin phone',
            'emergency contact number'],
      ),
      const DataField(
        name: 'family_name',
        label: 'Family name',
        kind: FieldKind.text,
        synonyms: <String>['surname', 'last name', 'family name'],
      ),
      const DataField(
        name: 'given_name',
        label: 'Given name',
        kind: FieldKind.text,
        synonyms: <String>['first name', 'given name', 'forename'],
      ),
    ],
  );

  static final DataTable encounters = DataTable(
    name: 'encounters',
    label: 'visits',
    singular: 'visit',
    synonyms: const <String>['visit', 'encounter', 'consultation',
        'attendance', 'seen', 'consult'],
    timeField: 'started_at',
    patientColumn: 'patient_id',
    fields: <DataField>[
      const DataField(
        name: 'type',
        label: 'Visit type',
        kind: FieldKind.categorical,
        synonyms: <String>['visit type', 'type of visit', 'kind of visit'],
        valueLabels: <String, String>{
          'new_visit': 'New',
          'newVisit': 'New',
          'follow_up': 'Follow-up',
          'followUp': 'Follow-up',
          'emergency': 'Emergency',
          'procedure': 'Procedure',
          'antenatal': 'Antenatal',
        },
      ),
      const DataField(
        name: 'status',
        label: 'Status',
        kind: FieldKind.categorical,
        synonyms: <String>['status', 'state'],
      ),
      const DataField(
        name: 'disposition',
        label: 'Disposition',
        kind: FieldKind.categorical,
        synonyms: <String>['disposition', 'outcome', 'result'],
      ),
      const DataField(
        name: 'provider_name',
        label: 'Clinician',
        kind: FieldKind.categorical,
        synonyms: <String>['clinician', 'doctor', 'provider', 'staff',
            'who saw them', 'seen by'],
      ),
      const DataField(
        name: 'referred_to',
        label: 'Referred to',
        kind: FieldKind.categorical,
        synonyms: <String>['referral', 'referred', 'referred to'],
      ),
      const DataField(
        name: 'started_at',
        label: 'Visit date',
        kind: FieldKind.temporal,
        synonyms: <String>['visit date', 'date', 'when', 'seen on'],
      ),
      DataField(
        name: 'length_minutes',
        label: 'Consultation length',
        kind: FieldKind.numeric,
        unit: 'min',
        synonyms: const <String>['length', 'duration', 'how long',
            'consultation length', 'time spent'],
        sources: const <String>['started_at', 'ended_at'],
        derive: (row) {
          final start = row['started_at'];
          final end = row['ended_at'];
          if (start is! int || end is! int || end <= start) return null;
          final minutes = (end - start) / 60000;
          // A visit spanning days is a record left open, not a long
          // consultation. Averaging those in makes every clinic look slow.
          return minutes > 600 ? null : minutes;
        },
      ),
      const DataField(
        name: 'chief_complaint',
        label: 'Presenting complaint',
        kind: FieldKind.text,
        synonyms: <String>['complaint', 'presenting complaint', 'reason',
            'chief complaint'],
      ),
    ],
  );

  static final DataTable appointments = DataTable(
    name: 'appointments',
    label: 'appointments',
    singular: 'appointment',
    synonyms: const <String>['appointment', 'booking', 'slot', 'schedule',
        'booked', 'clinic list'],
    timeField: 'scheduled_at',
    patientColumn: 'patient_id',
    fields: <DataField>[
      const DataField(
        name: 'status',
        label: 'Status',
        kind: FieldKind.categorical,
        synonyms: <String>['status', 'outcome', 'attendance'],
        valueLabels: <String, String>{
          'noShow': 'Did not attend',
          'no_show': 'Did not attend',
        },
      ),
      const DataField(
        name: 'type',
        label: 'Appointment type',
        kind: FieldKind.categorical,
        synonyms: <String>['appointment type', 'type'],
      ),
      const DataField(
        name: 'provider_name',
        label: 'Clinician',
        kind: FieldKind.categorical,
        synonyms: <String>['clinician', 'doctor', 'provider', 'with'],
      ),
      const DataField(
        name: 'duration_minutes',
        label: 'Slot length',
        kind: FieldKind.numeric,
        unit: 'min',
        synonyms: <String>['slot length', 'duration', 'appointment length'],
      ),
      const DataField(
        name: 'scheduled_at',
        label: 'Scheduled for',
        kind: FieldKind.temporal,
        synonyms: <String>['scheduled', 'booked for', 'date', 'when'],
      ),
      DataField(
        name: 'wait_minutes',
        label: 'Waiting time',
        kind: FieldKind.numeric,
        unit: 'min',
        higherIsBetter: false,
        synonyms: const <String>['wait', 'waiting time', 'waited',
            'time waiting', 'door to doctor'],
        sources: const <String>['arrived_at', 'started_at'],
        derive: (row) {
          final arrived = row['arrived_at'];
          final started = row['started_at'];
          if (arrived is! int || started is! int || started < arrived) {
            return null;
          }
          final minutes = (started - arrived) / 60000;
          return minutes > 720 ? null : minutes;
        },
      ),
      DataField(
        name: 'lateness_minutes',
        label: 'Running late by',
        kind: FieldKind.numeric,
        unit: 'min',
        higherIsBetter: false,
        synonyms: const <String>['late', 'lateness', 'running late', 'delay',
            'started late'],
        sources: const <String>['scheduled_at', 'started_at'],
        derive: (row) {
          final scheduled = row['scheduled_at'];
          final started = row['started_at'];
          if (scheduled is! int || started is! int) return null;
          final minutes = (started - scheduled) / 60000;
          return minutes.abs() > 720 ? null : minutes;
        },
      ),
      const DataField(
        name: 'reason',
        label: 'Reason',
        kind: FieldKind.text,
        synonyms: <String>['reason', 'booked for'],
      ),
    ],
  );

  static final DataTable vitals = DataTable(
    name: 'vitals',
    label: 'observations',
    singular: 'observation',
    synonyms: const <String>['vitals', 'observation', 'obs', 'reading',
        'measurement', 'vital signs'],
    timeField: 'recorded_at',
    patientColumn: 'patient_id',
    fields: <DataField>[
      const DataField(
        name: 'systolic_bp',
        label: 'Systolic BP',
        kind: FieldKind.numeric,
        unit: 'mmHg',
        higherIsBetter: false,
        // NICE stage-1 clinic threshold up; NEWS2 scoring floor down.
        screenHigh: 140,
        screenLow: 90,
        synonyms: <String>['systolic', 'sbp', 'blood pressure', 'bp',
            'top number', 'systolic blood pressure'],
      ),
      const DataField(
        name: 'diastolic_bp',
        label: 'Diastolic BP',
        kind: FieldKind.numeric,
        unit: 'mmHg',
        higherIsBetter: false,
        screenHigh: 90,
        synonyms: <String>['diastolic', 'dbp', 'bottom number',
            'diastolic blood pressure'],
      ),
      const DataField(
        name: 'heart_rate',
        label: 'Heart rate',
        kind: FieldKind.numeric,
        unit: 'bpm',
        screenHigh: 100,
        screenLow: 50,
        synonyms: <String>['heart rate', 'pulse', 'hr', 'bpm'],
      ),
      const DataField(
        name: 'respiratory_rate',
        label: 'Respiratory rate',
        kind: FieldKind.numeric,
        unit: '/min',
        screenHigh: 21,
        screenLow: 8,
        synonyms: <String>['respiratory rate', 'resp rate', 'rr',
            'breathing rate', 'breaths'],
      ),
      const DataField(
        name: 'temperature_c',
        label: 'Temperature',
        kind: FieldKind.numeric,
        unit: '°C',
        screenHigh: 38,
        screenLow: 36,
        synonyms: <String>['temperature', 'temp', 'fever', 'pyrexia'],
      ),
      const DataField(
        name: 'spo2',
        label: 'Oxygen saturation',
        kind: FieldKind.numeric,
        unit: '%',
        higherIsBetter: true,
        screenLow: 94,
        synonyms: <String>['spo2', 'sats', 'saturation', 'oxygen saturation',
            'o2 sats', 'oxygen'],
      ),
      const DataField(
        name: 'height_cm',
        label: 'Height',
        kind: FieldKind.numeric,
        unit: 'cm',
        synonyms: <String>['height', 'tall', 'stature'],
      ),
      const DataField(
        name: 'weight_kg',
        label: 'Weight',
        kind: FieldKind.numeric,
        unit: 'kg',
        synonyms: <String>['weight', 'mass', 'kg', 'kilos'],
      ),
      const DataField(
        name: 'bmi',
        label: 'BMI',
        kind: FieldKind.numeric,
        unit: 'kg/m²',
        screenHigh: 30,
        screenLow: 18.5,
        synonyms: <String>['bmi', 'body mass index'],
      ),
      const DataField(
        name: 'head_circumference_cm',
        label: 'Head circumference',
        kind: FieldKind.numeric,
        unit: 'cm',
        synonyms: <String>['head circumference', 'occipitofrontal', 'ofc'],
      ),
      const DataField(
        name: 'pain_score',
        label: 'Pain score',
        kind: FieldKind.numeric,
        higherIsBetter: false,
        screenHigh: 7,
        synonyms: <String>['pain', 'pain score'],
      ),
      const DataField(
        name: 'blood_glucose_mmol',
        label: 'Blood glucose',
        kind: FieldKind.numeric,
        unit: 'mmol/L',
        screenHigh: 11.1,
        screenLow: 4,
        synonyms: <String>['glucose', 'blood glucose', 'blood sugar', 'sugar',
            'bm', 'rbs'],
      ),
      const DataField(
        name: 'capillary_refill_sec',
        label: 'Capillary refill',
        kind: FieldKind.numeric,
        unit: 's',
        higherIsBetter: false,
        screenHigh: 3,
        synonyms: <String>['capillary refill', 'cap refill', 'crt'],
      ),
      const DataField(
        name: 'news2_score',
        label: 'NEWS2',
        kind: FieldKind.numeric,
        higherIsBetter: false,
        // The urgent-review trigger in the NEWS2 guidance itself.
        screenHigh: 5,
        synonyms: <String>['news2', 'news', 'early warning score', 'ews',
            'news score', 'deterioration score'],
      ),
      const DataField(
        name: 'news2_risk',
        label: 'NEWS2 risk',
        kind: FieldKind.categorical,
        synonyms: <String>['risk', 'news risk', 'risk band'],
      ),
      const DataField(
        name: 'consciousness',
        label: 'Consciousness',
        kind: FieldKind.categorical,
        synonyms: <String>['consciousness', 'avpu', 'alertness'],
      ),
      const DataField(
        name: 'heart_rhythm',
        label: 'Rhythm',
        kind: FieldKind.categorical,
        synonyms: <String>['rhythm', 'heart rhythm', 'regular irregular'],
      ),
      const DataField(
        name: 'on_oxygen',
        label: 'On oxygen',
        kind: FieldKind.boolean,
        synonyms: <String>['on oxygen', 'supplemental oxygen', 'oxygen therapy'],
      ),
      const DataField(
        name: 'recorded_by',
        label: 'Recorded by',
        kind: FieldKind.categorical,
        synonyms: <String>['recorded by', 'taken by', 'staff', 'nurse'],
      ),
      const DataField(
        name: 'recorded_at',
        label: 'Recorded',
        kind: FieldKind.temporal,
        synonyms: <String>['recorded', 'date', 'when', 'taken'],
      ),
    ],
  );

  static final DataTable notes = DataTable(
    name: 'clinical_notes',
    label: 'notes',
    singular: 'note',
    synonyms: const <String>['note', 'soap', 'documentation', 'write up',
        'clinical note'],
    timeField: 'created_at',
    patientColumn: 'patient_id',
    fields: <DataField>[
      const DataField(
        name: 'note_type',
        label: 'Note type',
        kind: FieldKind.categorical,
        synonyms: <String>['note type', 'type'],
      ),
      const DataField(
        name: 'status',
        label: 'Status',
        kind: FieldKind.categorical,
        synonyms: <String>['status', 'signed', 'draft'],
      ),
      const DataField(
        name: 'signed_by',
        label: 'Signed by',
        kind: FieldKind.categorical,
        synonyms: <String>['signed by', 'author', 'written by'],
      ),
      const DataField(
        name: 'created_at',
        label: 'Written',
        kind: FieldKind.temporal,
        synonyms: <String>['written', 'created', 'date', 'when'],
      ),
      DataField(
        name: 'sign_delay_hours',
        label: 'Time to sign',
        kind: FieldKind.numeric,
        unit: 'h',
        higherIsBetter: false,
        synonyms: const <String>['time to sign', 'signing delay',
            'how long to sign', 'sign delay'],
        sources: const <String>['created_at', 'signed_at'],
        derive: (row) {
          final created = row['created_at'];
          final signed = row['signed_at'];
          if (created is! int || signed is! int || signed < created) {
            return null;
          }
          return (signed - created) / 3600000;
        },
      ),
      const DataField(
        name: 'subjective',
        label: 'Subjective',
        kind: FieldKind.text,
        synonyms: <String>['subjective', 'history'],
      ),
      const DataField(
        name: 'assessment',
        label: 'Assessment',
        kind: FieldKind.text,
        synonyms: <String>['assessment', 'impression'],
      ),
      const DataField(
        name: 'plan',
        label: 'Plan',
        kind: FieldKind.text,
        synonyms: <String>['plan', 'management'],
      ),
    ],
  );

  static final DataTable medications = DataTable(
    name: 'medications',
    label: 'medications',
    singular: 'medication',
    synonyms: const <String>['medication', 'drug', 'prescription', 'meds',
        'medicine', 'prescribed'],
    timeField: 'created_at',
    patientColumn: 'patient_id',
    fields: <DataField>[
      const DataField(
        name: 'name',
        label: 'Drug',
        kind: FieldKind.categorical,
        synonyms: <String>['drug', 'drug name', 'medicine', 'medication name'],
      ),
      const DataField(
        name: 'route',
        label: 'Route',
        kind: FieldKind.categorical,
        synonyms: <String>['route', 'given how'],
      ),
      const DataField(
        name: 'frequency',
        label: 'Frequency',
        kind: FieldKind.categorical,
        synonyms: <String>['frequency', 'how often'],
      ),
      const DataField(
        name: 'status',
        label: 'Status',
        kind: FieldKind.categorical,
        synonyms: <String>['status', 'active stopped'],
      ),
      const DataField(
        name: 'prescriber',
        label: 'Prescriber',
        kind: FieldKind.categorical,
        synonyms: <String>['prescriber', 'prescribed by', 'who prescribed'],
      ),
      const DataField(
        name: 'indication',
        label: 'Indication',
        kind: FieldKind.categorical,
        synonyms: <String>['indication', 'prescribed for', 'what for'],
      ),
      const DataField(
        name: 'created_at',
        label: 'Prescribed',
        kind: FieldKind.temporal,
        synonyms: <String>['prescribed', 'date', 'when'],
      ),
    ],
  );

  static final DataTable problems = DataTable(
    name: 'problems',
    label: 'diagnoses',
    singular: 'diagnosis',
    synonyms: const <String>['problem', 'diagnosis', 'diagnoses', 'condition',
        'disease', 'problem list'],
    timeField: 'created_at',
    patientColumn: 'patient_id',
    fields: <DataField>[
      const DataField(
        name: 'display',
        label: 'Diagnosis',
        kind: FieldKind.categorical,
        synonyms: <String>['diagnosis', 'condition', 'problem', 'disease'],
      ),
      const DataField(
        name: 'status',
        label: 'Status',
        kind: FieldKind.categorical,
        synonyms: <String>['status', 'active resolved'],
      ),
      const DataField(
        name: 'is_chronic',
        label: 'Chronic',
        kind: FieldKind.boolean,
        synonyms: <String>['chronic', 'long term'],
      ),
      const DataField(
        name: 'onset_date',
        label: 'Onset',
        kind: FieldKind.temporal,
        synonyms: <String>['onset', 'started', 'began'],
      ),
      const DataField(
        name: 'created_at',
        label: 'Recorded',
        kind: FieldKind.temporal,
        synonyms: <String>['recorded', 'added', 'date'],
      ),
    ],
  );

  static final DataTable allergies = DataTable(
    name: 'allergies',
    label: 'allergies',
    singular: 'allergy',
    synonyms: const <String>['allergy', 'allergen', 'allergic', 'intolerance'],
    timeField: 'created_at',
    patientColumn: 'patient_id',
    fields: <DataField>[
      const DataField(
        name: 'substance',
        label: 'Substance',
        kind: FieldKind.categorical,
        synonyms: <String>['substance', 'allergen', 'allergic to'],
      ),
      const DataField(
        name: 'category',
        label: 'Category',
        kind: FieldKind.categorical,
        synonyms: <String>['category', 'kind'],
      ),
      const DataField(
        name: 'severity',
        label: 'Severity',
        kind: FieldKind.categorical,
        synonyms: <String>['severity', 'how severe', 'seriousness'],
      ),
      const DataField(
        name: 'status',
        label: 'Status',
        kind: FieldKind.categorical,
        synonyms: <String>['status'],
      ),
      const DataField(
        name: 'created_at',
        label: 'Recorded',
        kind: FieldKind.temporal,
        synonyms: <String>['recorded', 'date'],
      ),
    ],
  );

  static final DataTable attachments = DataTable(
    name: 'attachments',
    label: 'files',
    singular: 'file',
    synonyms: const <String>['file', 'attachment', 'photo', 'image',
        'picture', 'document', 'scan', 'recording'],
    timeField: 'created_at',
    patientColumn: 'patient_id',
    fields: <DataField>[
      const DataField(
        name: 'kind',
        label: 'Kind',
        kind: FieldKind.categorical,
        synonyms: <String>['kind', 'type of file', 'file type'],
      ),
      const DataField(
        name: 'body_site',
        label: 'Body site',
        kind: FieldKind.categorical,
        synonyms: <String>['body site', 'site', 'where on the body'],
      ),
      const DataField(
        name: 'size_bytes',
        label: 'File size',
        kind: FieldKind.numeric,
        unit: 'bytes',
        synonyms: <String>['size', 'file size', 'how big'],
      ),
      const DataField(
        name: 'duration_ms',
        label: 'Recording length',
        kind: FieldKind.numeric,
        unit: 'ms',
        synonyms: <String>['recording length', 'audio length'],
      ),
      const DataField(
        name: 'created_at',
        label: 'Added',
        kind: FieldKind.temporal,
        synonyms: <String>['added', 'captured', 'date', 'when'],
      ),
    ],
  );
}
