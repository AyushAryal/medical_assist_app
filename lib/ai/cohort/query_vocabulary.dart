import '../../clinical/explanations.dart';
import 'cohort_query.dart';
import '../../clinical/insights/note_intelligence.dart';

/// A set of one-tap questions with a reason for existing.
class QueryStarterGroup {
  const QueryStarterGroup({
    required this.title,
    required this.icon,
    required this.reason,
    required this.starters,
  });

  final String title;

  /// A name the UI maps to an icon, so this stays free of Flutter.
  final String icon;

  /// Why a clinician would want these. A list of example queries teaches the
  /// syntax; a reason teaches what the feature is *for*, which is what people
  /// actually need to be told.
  final String reason;

  final List<String> starters;
}

/// One searchable field, described for a human rather than for a database.
class QueryField {
  const QueryField({
    required this.name,
    required this.column,
    required this.holds,
    required this.phrasings,
    this.caveat,
  });

  /// What a clinician would call it.
  final String name;

  /// The underlying column, so the reference is checkable against the schema.
  final String column;

  final String holds;

  /// Ways of asking for it that actually work.
  final List<String> phrasings;

  /// What it will not find. Present wherever the honest answer is "less than
  /// you might assume".
  final String? caveat;
}

/// What the search understands, published so it can be learned.
///
/// A natural-language search that cannot say what it knows is a guessing game:
/// the user tries phrasings until something works, and has no way to tell a
/// question the app cannot answer from one it answered wrongly. So the
/// vocabulary is data rather than buried in regular expressions — the router
/// matches on these words and the guide displays these words, which is what
/// keeps what is advertised and what works from drifting apart.
abstract final class QueryVocabulary {
  /// Fields searchable on each table.
  static Map<QueryEntity, List<QueryField>> get fields =>
      <QueryEntity, List<QueryField>>{
        QueryEntity.patients: <QueryField>[
          const QueryField(
            name: 'Name',
            column: 'patients.family_name, patients.given_name',
            holds: 'Family and given names.',
            phrasings: <String>[
              'name starting with A',
              'surname Aryal',
              'called Sita',
            ],
          ),
          const QueryField(
            name: 'MRN',
            column: 'patients.mrn',
            holds: 'The six-digit record number.',
            phrasings: <String>['mrn 004512', 'record number 004512'],
          ),
          const QueryField(
            name: 'Age',
            column: 'patients.date_of_birth',
            holds: 'Worked out from the recorded date of birth, as at today.',
            phrasings: <String>[
              'under fives',
              'children',
              'over 65s',
              'adults',
            ],
            caveat: 'A patient with no recorded date of birth cannot be placed '
                'in an age band and is left out of every one.',
          ),
          const QueryField(
            name: 'Sex at birth',
            column: 'patients.sex_at_birth',
            holds: 'Drives reference ranges and dosing, not how the patient is '
                'addressed.',
            phrasings: <String>['female patients', 'male patients'],
          ),
          const QueryField(
            name: 'Medicine',
            column: 'medications.name',
            holds: 'Active prescriptions. Matched on the start of the name, so '
                '"warfarin" finds "Warfarin 3mg".',
            phrasings: <String>['on warfarin', 'taking metformin'],
            caveat: 'Only medicines added to the medication list. A drug '
                'written into note text but never added there will not be '
                'found.',
          ),
          const QueryField(
            name: 'Condition',
            column: 'problems.display',
            holds: 'Active problem list entries.',
            phrasings: <String>['diabetics', 'with asthma', 'hypertensive'],
            caveat: 'Only diagnoses added to the problem list. A resolved '
                'problem does not count.',
          ),
          const QueryField(
            name: 'Allergy',
            column: 'allergies.substance',
            holds: 'Active recorded allergies.',
            phrasings: <String>['allergic to penicillin'],
          ),
          const QueryField(
            name: 'Last seen',
            column: 'patients.last_seen_at',
            holds: 'The most recent visit, used for overdue lists.',
            phrasings: <String>[
              'not seen in 6 months',
              'overdue for review',
            ],
            caveat: 'Patients never seen at all are included — that is who an '
                'overdue list is for.',
          ),
        ],
        QueryEntity.appointments: <QueryField>[
          const QueryField(
            name: 'When',
            column: 'appointments.scheduled_at',
            holds: 'The booked date and time.',
            phrasings: <String>[
              'appointments this month',
              'bookings next week',
              'appointments today',
            ],
          ),
          const QueryField(
            name: 'Status',
            column: 'appointments.status',
            holds: 'Where the booking reached in the front-desk workflow.',
            phrasings: <String>[
              'cancelled appointments',
              'did not attend',
              'no shows',
              'completed appointments',
            ],
          ),
          const QueryField(
            name: 'Patient',
            column: 'appointments.patient_id',
            holds: 'Every patient filter can be combined with an appointment '
                'question.',
            phrasings: <String>['diabetics with appointments this week'],
          ),
        ],
        QueryEntity.vitals: <QueryField>[
          const QueryField(
            name: 'Early warning score',
            column: 'vitals.news2_score',
            holds: 'The NEWS2 total calculated when the set was recorded.',
            phrasings: <String>[
              'observations with news2 above 5',
              'early warning score over 7',
            ],
            caveat: 'Only sets NEWS2 could score. Children, pregnant patients '
                'and incomplete sets carry no score and cannot match.',
          ),
          const QueryField(
            name: 'Blood pressure',
            column: 'vitals.systolic_bp',
            holds: 'Systolic pressure in mmHg.',
            phrasings: <String>['bp over 160', 'systolic above 180'],
          ),
          const QueryField(
            name: 'Abnormal',
            column: 'vitals.*',
            holds: 'Any value outside the adult reference band.',
            phrasings: <String>['abnormal observations this week'],
            caveat: 'Uses adult bounds. Age-banded paediatric flagging happens '
                'when an observation is displayed and is not applied here, so '
                'an abnormal set in a small child may not match.',
          ),
          const QueryField(
            name: 'When',
            column: 'vitals.recorded_at',
            holds: 'When the observations were taken.',
            phrasings: <String>['observations today'],
          ),
        ],
        QueryEntity.notes: <QueryField>[
          const QueryField(
            name: 'Status',
            column: 'clinical_notes.status',
            holds: 'Draft or signed. Drafts are unfinished charting.',
            phrasings: <String>['unsigned notes', 'draft notes'],
          ),
          const QueryField(
            name: 'When',
            column: 'clinical_notes.created_at',
            holds: 'When the note was started.',
            phrasings: <String>['notes from last week'],
          ),
        ],
        QueryEntity.files: <QueryField>[
          const QueryField(
            name: 'Kind',
            column: 'attachments.kind',
            holds: 'Photo, document or recording.',
            phrasings: <String>[
              'photos from last week',
              'recordings this month',
            ],
          ),
          const QueryField(
            name: 'When',
            column: 'attachments.created_at',
            holds: 'When the file was attached.',
            phrasings: <String>['files added today'],
          ),
        ],
        QueryEntity.visits: <QueryField>[
          const QueryField(
            name: 'When',
            column: 'encounters.started_at',
            holds: 'When the consultation began.',
            phrasings: <String>[
              'how many visits last month',
              'patients seen this week',
            ],
          ),
          const QueryField(
            name: 'Type',
            column: 'encounters.type',
            holds: 'New, follow-up, emergency, procedure, antenatal and so on.',
            phrasings: <String>['antenatal visits this month'],
          ),
        ],
      };

  /// Everything the search knows how to look for, as a reference sheet.
  static MetricExplanation schemaReference() {
    final rows = <ExplainRow>[];
    for (final entry in fields.entries) {
      rows.add(
        ExplainRow(
          label: '── ${entry.key.label} ──',
          value: '',
          note: entry.key.holds,
        ),
      );
      for (final field in entry.value) {
        rows.add(
          ExplainRow(
            label: field.name,
            value: field.phrasings.map((p) => '"$p"').join('  ·  '),
            note: field.caveat == null
                ? field.column
                : '${field.column} — ${field.caveat}',
          ),
        );
      }
    }

    return MetricExplanation(
      title: 'What the search understands',
      summary: 'The full vocabulary, and the field each phrase maps onto. '
          'Nothing outside this list is understood — the search says so rather '
          'than guessing.',
      method: <String>[
        'Name a table to search it: '
            '${QueryEntity.values.map((e) => e.triggerWords.first).join(', ')}. '
            'Without one, patients are searched.',
        'Filters combine. "Diabetics under 5 seen last month" applies all '
            'three at once.',
        'Every answer lists the filters it used, so a misread question shows '
            'itself.',
        'No SQL is written from your words. Phrases select from the fields '
            'below, and the query that runs is one of a handful that were '
            'written by hand and tested.',
      ],
      derivation: rows,
      confidence: ExplainConfidence.measured,
      source: 'This device\'s schema — see SystemSchema.md',
      caveat: 'Structured fields drive the answer. Free text inside notes is '
          'searched too, but only as a secondary "also mentioned" list — a '
          'note records what was true the day it was written, not what is true '
          'now. The access log is deliberately not searchable from here: who '
          'opened which record is reviewed in Settings › Access log, where the '
          'act of reviewing it is itself recorded.',
    );
  }

  /// The words that pick a table, for the short in-line hint.
  static MetricExplanation tableHint() {
    return MetricExplanation(
      title: 'Choosing what to search',
      summary: 'A word in your question decides which table is searched. '
          'Without one, patients are searched.',
      method: const <String>[
        'Say "patient" or "who" to search the register.',
        'Say "appointment", "booking" or "no show" to search booked slots — '
            'including ones nobody attended.',
        'Say "visit", "seen" or "consultation" to search consultations that '
            'actually happened.',
        'The difference matters: "appointments last month" counts what was '
            'booked, "visits last month" counts what happened, and a busy '
            'clinic with many non-attenders has very different numbers for '
            'the two.',
      ],
      derivation: <ExplainRow>[
        for (final entity in QueryEntity.values)
          ExplainRow(
            label: entity.label,
            value: entity.triggerWords.take(5).join(', '),
            note: entity.holds,
          ),
      ],
      confidence: ExplainConfidence.measured,
    );
  }

  /// Suggestions shown when a question was not understood, chosen to teach the
  /// vocabulary rather than merely to fill the screen.
  static List<String> suggestionsFor(String question) {
    final text = question.toLowerCase();
    final out = <String>[];

    if (RegExp(r'\bname|\bcalled\b|\bsurname\b').hasMatch(text)) {
      out.add('patients with name starting with A');
    }
    if (QueryEntity.appointments.triggerWords.any(text.contains)) {
      out.add('appointments this month');
      out.add('appointments that were cancelled this month');
    }
    if (RegExp(r'\bdrug|\bmedicine|\bmedication\b').hasMatch(text)) {
      out.add('everyone on warfarin');
    }
    if (out.isEmpty) {
      out.addAll(<String>[
        'patients with name starting with A',
        'appointments this month',
        'everyone on warfarin',
      ]);
    }
    return out.take(4).toList();
  }

  /// The things worth offering as one tap, grouped by what they are for.
  ///
  /// Buttons are not decoration here, they are *input*. With nothing to go on
  /// the interpreter has to infer an entire question from free text; with a
  /// tap it is handed an unambiguous one. Every entry below is a phrase the
  /// pattern matcher answers without help, which means a starter is never a
  /// promise the app cannot keep — and each is a real clinical task rather
  /// than a demonstration of the search.
  static List<QueryStarterGroup> get starters => <QueryStarterGroup>[
        const QueryStarterGroup(
          title: 'Safety',
          icon: 'shield',
          reason: 'The lists you need when a guideline changes or a drug is '
              'recalled.',
          starters: <String>[
            'everyone on warfarin',
            'patients allergic to penicillin',
            'observations with news2 above 5',
          ],
        ),
        const QueryStarterGroup(
          title: 'Falling out of care',
          icon: 'overdue',
          reason: 'People who have quietly stopped coming.',
          starters: <String>[
            'diabetics not seen in 6 months',
            'hypertensive patients overdue for review',
            'patients never seen',
          ],
        ),
        const QueryStarterGroup(
          title: 'Who stands out',
          icon: 'rank',
          reason: 'Measured readings ranked or screened — not the problem '
              'list, and the two can legitimately disagree.',
          starters: <String>[
            'riskiest patients',
            'patients with high bp',
            'top 10 patients by bmi',
          ],
        ),
        const QueryStarterGroup(
          title: 'Today and this week',
          icon: 'today',
          reason: 'What is booked, what happened, what is unfinished.',
          starters: <String>[
            'appointments today',
            'unsigned notes',
            'how many visits last month',
          ],
        ),
        const QueryStarterGroup(
          title: 'Reporting',
          icon: 'chart',
          reason: 'Shapes rather than lists — what a monthly report needs.',
          starters: <String>[
            'clinic dashboard',
            'visits per week',
            'patients by age band',
          ],
        ),
        const QueryStarterGroup(
          title: 'Finding someone',
          icon: 'person',
          reason: 'The front-desk questions.',
          starters: <String>[
            'patients with name starting with A',
            'patients and their contact numbers',
            'latest patients',
          ],
        ),
      ];

  /// The condition words the router knows, for the guide.
  static List<String> get knownConditions =>
      NoteIntelligence.knownProblems.values.toList()..sort();

  /// The drug names the router knows, for the guide.
  static List<String> get knownMedicines =>
      NoteIntelligence.knownMedications.toList()..sort();
}
