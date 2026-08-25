import '../../clinical/explanations.dart';

/// What kind of question is being asked. Decides how the answer is presented —
/// a recall wants a list of names to act on, an activity question wants a
/// number.
/// Which table a question is about.
///
/// Naming this explicitly is what lets the app *teach* its vocabulary: each
/// entity below advertises the words that select it, so a question that found
/// nothing can say "say 'appointment' to search bookings" instead of shrugging.
enum QueryEntity {
  /// The register itself — people, and what is recorded about them.
  patients,

  /// Booked slots, including ones nobody attended.
  appointments,

  /// Consultations that actually happened.
  visits,

  /// Recorded observation sets — blood pressure, pulse, early warning scores.
  vitals,

  /// Clinical notes, including unsigned drafts.
  notes,

  /// Photos, documents and recordings attached to a record.
  files,
}

extension QueryEntityX on QueryEntity {
  String get label => switch (this) {
        QueryEntity.patients => 'Patients',
        QueryEntity.appointments => 'Appointments',
        QueryEntity.visits => 'Visits',
        QueryEntity.vitals => 'Observations',
        QueryEntity.notes => 'Notes',
        QueryEntity.files => 'Files',
      };

  String get noun => switch (this) {
        QueryEntity.patients => 'patient',
        QueryEntity.appointments => 'appointment',
        QueryEntity.visits => 'visit',
        QueryEntity.vitals => 'observation set',
        QueryEntity.notes => 'note',
        QueryEntity.files => 'file',
      };

  /// What this table holds, for the schema reference.
  String get holds => switch (this) {
        QueryEntity.patients =>
          'One row per person on the register, with their demographics, and '
              'links to their problems, medicines and allergies.',
        QueryEntity.appointments =>
          'One row per booked slot — including cancellations and people who '
              'did not attend, because a missed appointment is a clinical '
              'signal and only exists if it is kept.',
        QueryEntity.visits =>
          'One row per consultation that actually took place, with its type, '
              'presenting complaint and outcome.',
        QueryEntity.vitals =>
          'One row per set of observations taken at the bedside, with the '
              'early warning score that was calculated at the time.',
        QueryEntity.notes =>
          'One row per clinical note, including drafts that were never '
              'signed — which is what makes unfinished charting findable.',
        QueryEntity.files =>
          'Photos, documents and voice recordings attached to a note or a '
              'patient.',
      };

  /// The words that select this table. Shown in the guide, and matched by the
  /// router — one list, so what is advertised is what works.
  List<String> get triggerWords => switch (this) {
        QueryEntity.patients => const <String>[
            'patient', 'patients', 'people', 'register', 'who',
          ],
        QueryEntity.appointments => const <String>[
            'appointment', 'appointments', 'booking', 'bookings', 'booked',
            'scheduled', 'slot', 'slots', 'clinic list', 'did not attend',
            'no show', 'no-show', 'cancelled', 'dna',
          ],
        QueryEntity.visits => const <String>[
            'visit', 'visits', 'seen', 'consultation', 'consultations',
            'encounter', 'encounters', 'attended',
          ],
        QueryEntity.vitals => const <String>[
            'observation', 'observations', 'vitals', 'vital signs', 'obs',
            'news2', 'news', 'early warning', 'blood pressure', 'bp',
            'pulse', 'temperature', 'saturation', 'spo2',
          ],
        QueryEntity.notes => const <String>[
            'note', 'notes', 'unsigned', 'draft', 'drafts', 'charting',
            'documentation',
          ],
        QueryEntity.files => const <String>[
            'file', 'files', 'photo', 'photos', 'image', 'images',
            'picture', 'pictures', 'document', 'documents', 'attachment',
            'attachments', 'recording', 'recordings', 'audio',
          ],
      };
}

enum CohortQueryKind {
  /// "Everyone on warfarin." A list to act on, one patient per row.
  recall,

  /// "Diabetics not seen in six months." People who have fallen out of care.
  overdue,

  /// "How many did we see last month." A count, not a list.
  activity,

  /// "Under-fives with diarrhoea last month." A count with a list behind it.
  cohort,
}

extension CohortQueryKindX on CohortQueryKind {
  String get label => switch (this) {
        CohortQueryKind.recall => 'Recall list',
        CohortQueryKind.overdue => 'Overdue follow-up',
        CohortQueryKind.activity => 'Clinic activity',
        CohortQueryKind.cohort => 'Cohort',
      };

  /// Whether the result is primarily a list of people rather than a number.
  bool get listsPatients => this != CohortQueryKind.activity;
}

/// Age bands the UI offers. Deliberately the bands clinicians already use for
/// reporting rather than arbitrary ranges.
enum AgeBand { under1, under5, child, adolescent, adult, over65 }

extension AgeBandX on AgeBand {
  String get label => switch (this) {
        AgeBand.under1 => 'Under 1',
        AgeBand.under5 => 'Under 5',
        AgeBand.child => '5–11',
        AgeBand.adolescent => '12–17',
        AgeBand.adult => '18–64',
        AgeBand.over65 => '65 and over',
      };

  /// Inclusive lower bound in years.
  int get minYears => switch (this) {
        AgeBand.under1 => 0,
        AgeBand.under5 => 0,
        AgeBand.child => 5,
        AgeBand.adolescent => 12,
        AgeBand.adult => 18,
        AgeBand.over65 => 65,
      };

  /// Exclusive upper bound in years, or null for no upper bound.
  int? get maxYears => switch (this) {
        AgeBand.under1 => 1,
        AgeBand.under5 => 5,
        AgeBand.child => 12,
        AgeBand.adolescent => 18,
        AgeBand.adult => 65,
        AgeBand.over65 => null,
      };
}

/// A question about the register, expressed as filters rather than as SQL.
///
/// This is the whole safety argument for the query feature. A language model
/// that writes SQL can be confidently wrong in a way nobody catches: a
/// recall list that quietly misses three patients looks exactly like a correct
/// one, and there is no second reader, because the entire point is that the
/// clinician could not run the query themselves.
///
/// So no SQL is ever generated. A model — if one is installed at all — only
/// chooses among filters that a human wrote and a test suite checks, which is
/// classification rather than generation, and the filters it chose are shown
/// back in plain English on every result. A wrong *match* is therefore visible;
/// a wrong *query* is impossible.
class CohortQuery {
  const CohortQuery({
    required this.kind,
    this.entity = QueryEntity.patients,
    this.nameStartsWith,
    this.nameContains,
    this.mrn,
    this.appointmentStatus,
    this.noteStatus,
    this.news2AtLeast,
    this.systolicAtLeast,
    this.abnormalOnly = false,
    this.fileKind,
    this.mostRecent,
    this.anyTextOf = const <String>[],
    this.medication,
    this.problem,
    this.allergy,
    this.ageBand,
    this.sexAtBirth,
    this.notSeenSince,
    this.periodFrom,
    this.periodTo,
    this.clinicId,
    this.visitType,
    this.includeDeceased = false,
  });

  final CohortQueryKind kind;

  /// Which table is being asked about.
  final QueryEntity entity;

  /// Family or given name beginning with this. The single most common thing a
  /// front desk actually needs — "the Aryals", "someone beginning with A" —
  /// and its absence was the clearest sign the first vocabulary was built
  /// around clinical questions rather than around the desk.
  final String? nameStartsWith;

  /// Family or given name containing this.
  final String? nameContains;

  /// Exact medical record number.
  final String? mrn;

  /// Restricts to appointments in this state.
  final String? appointmentStatus;

  /// Note status — `draft` finds unfinished charting.
  final String? noteStatus;

  /// Minimum early warning score. The number a deteriorating-patient search is
  /// actually about.
  final int? news2AtLeast;

  /// Minimum systolic pressure, for a hypertension sweep.
  final int? systolicAtLeast;

  /// Only observation sets containing a value outside its reference range.
  final bool abnormalOnly;

  /// Restricts to one kind of attachment — `photo`, `document`, `audio`.
  final String? fileKind;

  /// Newest first, and how many. "Latest patients", "last 5 visits".
  final int? mostRecent;

  /// Words to look for anywhere in the free text, when they match no
  /// structured field. Any of them counts — "coffee or tea" is one filter with
  /// two terms.
  final List<String> anyTextOf;

  /// Matched as a prefix against the drug name, so "warfarin" finds
  /// "Warfarin 3mg". Getting this wrong in either direction is the failure
  /// this whole design exists to prevent, so it is one hand-written, tested
  /// clause rather than something generated per question.
  final String? medication;

  final String? problem;
  final String? allergy;
  final AgeBand? ageBand;
  final String? sexAtBirth;

  /// Patients whose most recent visit is older than this, or who have never
  /// been seen at all.
  final DateTime? notSeenSince;

  final DateTime? periodFrom;
  final DateTime? periodTo;
  final String? clinicId;
  final String? visitType;

  /// Off by default. A recall list that telephones the dead is the kind of
  /// error a clinic does not recover from socially, whatever the data says.
  final bool includeDeceased;

  /// The term worth looking for in free text, if any.
  ///
  /// Structured filters are the answer; this is the safety net for the case
  /// they cannot cover — a drug or diagnosis written into a note but never
  /// added to the list it belongs on.
  String? get freeTextTerm =>
      medication ?? problem ?? allergy ?? nameContains ?? anyTextOf.firstOrNull;

  /// True when the only thing to go on is words to look for in prose.
  ///
  /// This distinction is load-bearing. A query with no structured filter
  /// matches *everything*, so answering one by counting patients reports the
  /// whole register — "hello" came back as "I found 13 patients", which is
  /// both wrong and confidently stated. A text-only question has to be
  /// answered by the text search or not at all.
  bool get isTextOnly =>
      anyTextOf.isNotEmpty &&
      medication == null &&
      problem == null &&
      allergy == null &&
      nameStartsWith == null &&
      nameContains == null &&
      mrn == null &&
      ageBand == null &&
      sexAtBirth == null &&
      notSeenSince == null &&
      periodFrom == null &&
      appointmentStatus == null &&
      noteStatus == null &&
      news2AtLeast == null &&
      systolicAtLeast == null &&
      !abnormalOnly &&
      fileKind == null &&
      mostRecent == null;

  /// Every term worth looking for in free text.
  List<String> get freeTextTerms => <String>[
        if (anyTextOf.isNotEmpty) ...anyTextOf else ?freeTextTerm,
      ];

  bool get isEmpty =>
      nameStartsWith == null &&
      nameContains == null &&
      mrn == null &&
      appointmentStatus == null &&
      noteStatus == null &&
      news2AtLeast == null &&
      systolicAtLeast == null &&
      !abnormalOnly &&
      fileKind == null &&
      mostRecent == null &&
      anyTextOf.isEmpty &&
      medication == null &&
      problem == null &&
      allergy == null &&
      ageBand == null &&
      sexAtBirth == null &&
      notSeenSince == null &&
      periodFrom == null &&
      clinicId == null &&
      visitType == null;

  CohortQuery copyWith({
    CohortQueryKind? kind,
    QueryEntity? entity,
    String? nameStartsWith,
    String? nameContains,
    String? mrn,
    String? appointmentStatus,
    String? noteStatus,
    int? news2AtLeast,
    int? systolicAtLeast,
    bool? abnormalOnly,
    String? fileKind,
    int? mostRecent,
    List<String>? anyTextOf,
    String? medication,
    String? problem,
    String? allergy,
    AgeBand? ageBand,
    String? sexAtBirth,
    DateTime? notSeenSince,
    DateTime? periodFrom,
    DateTime? periodTo,
    String? clinicId,
    String? visitType,
    bool? includeDeceased,
    Set<String> clear = const <String>{},
  }) {
    T? keep<T>(String name, T? replacement, T? current) =>
        clear.contains(name) ? null : (replacement ?? current);

    return CohortQuery(
      kind: kind ?? this.kind,
      entity: entity ?? this.entity,
      nameStartsWith:
          keep('nameStartsWith', nameStartsWith, this.nameStartsWith),
      nameContains: keep('nameContains', nameContains, this.nameContains),
      mrn: keep('mrn', mrn, this.mrn),
      appointmentStatus:
          keep('appointmentStatus', appointmentStatus, this.appointmentStatus),
      noteStatus: keep('noteStatus', noteStatus, this.noteStatus),
      news2AtLeast: keep('news2AtLeast', news2AtLeast, this.news2AtLeast),
      systolicAtLeast:
          keep('systolicAtLeast', systolicAtLeast, this.systolicAtLeast),
      abnormalOnly: abnormalOnly ?? this.abnormalOnly,
      fileKind: keep('fileKind', fileKind, this.fileKind),
      mostRecent: keep('mostRecent', mostRecent, this.mostRecent),
      anyTextOf: clear.contains('anyTextOf')
          ? const <String>[]
          : (anyTextOf ?? this.anyTextOf),
      medication: keep('medication', medication, this.medication),
      problem: keep('problem', problem, this.problem),
      allergy: keep('allergy', allergy, this.allergy),
      ageBand: keep('ageBand', ageBand, this.ageBand),
      sexAtBirth: keep('sexAtBirth', sexAtBirth, this.sexAtBirth),
      notSeenSince: keep('notSeenSince', notSeenSince, this.notSeenSince),
      periodFrom: keep('periodFrom', periodFrom, this.periodFrom),
      periodTo: keep('periodTo', periodTo, this.periodTo),
      clinicId: keep('clinicId', clinicId, this.clinicId),
      visitType: keep('visitType', visitType, this.visitType),
      includeDeceased: includeDeceased ?? this.includeDeceased,
    );
  }

  /// The filters, in clinical English, one per line.
  ///
  /// Shown on every result. This is what makes a wrong interpretation visible:
  /// a clinician who asked for warfarin and reads "Taking a medicine starting
  /// with 'warfarin'" knows the question was understood, and one who reads
  /// something else knows immediately that it was not.
  List<String> describe() {
    final parts = <String>['Searching ${entity.label.toLowerCase()}'];

    if (nameStartsWith != null) {
      parts.add('Name starts with "$nameStartsWith"');
    }
    if (nameContains != null) {
      parts.add('Name contains "$nameContains"');
    }
    if (mrn != null) parts.add('MRN is $mrn');
    if (appointmentStatus != null) {
      parts.add('Appointment status: $appointmentStatus');
    }
    if (noteStatus != null) {
      parts.add(
        noteStatus == 'draft'
            ? 'Note is still a draft — not signed'
            : 'Note status: $noteStatus',
      );
    }
    if (news2AtLeast != null) {
      parts.add('Early warning score of $news2AtLeast or more');
    }
    if (systolicAtLeast != null) {
      parts.add('Systolic pressure of $systolicAtLeast mmHg or more');
    }
    if (abnormalOnly) {
      parts.add('At least one observation outside its reference range');
    }
    if (fileKind != null) parts.add('File type: $fileKind');
    if (mostRecent != null) parts.add('The $mostRecent most recent');
    if (anyTextOf.isNotEmpty) {
      parts.add(
        'Text mentioning ${anyTextOf.map((t) => '"$t"').join(' or ')}',
      );
    }
    if (medication != null) {
      parts.add('Taking a medicine whose name starts with "$medication"');
    }
    if (problem != null) {
      parts.add('Has "$problem" on the active problem list');
    }
    if (allergy != null) {
      parts.add('Has a recorded allergy to "$allergy"');
    }
    if (ageBand != null) {
      parts.add('Aged ${ageBand!.label.toLowerCase()}');
    }
    if (sexAtBirth != null) {
      parts.add('Sex at birth recorded as $sexAtBirth');
    }
    if (notSeenSince != null) {
      parts.add(
        'Last seen before ${_date(notSeenSince!)}, or never seen',
      );
    }
    if (periodFrom != null) {
      final verb = entity == QueryEntity.appointments ? 'Booked' : 'Seen';
      parts.add(
        periodTo == null
            ? '$verb on or after ${_date(periodFrom!)}'
            : '$verb between ${_date(periodFrom!)} and ${_date(periodTo!)}',
      );
    }
    if (visitType != null) parts.add('Visit type: $visitType');
    if (clinicId != null) parts.add('At the selected clinic only');

    parts.add(
      includeDeceased
          ? 'Including patients recorded as deceased'
          : 'Excluding patients recorded as deceased',
    );
    return parts;
  }

  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// What this query does and does not find.
  MetricExplanation explain({int? resultCount}) {
    return MetricExplanation(
      title: kind.label,
      summary: resultCount == null
          ? 'A search of this device\'s register, using the filters below.'
          : '$resultCount ${resultCount == 1 ? 'patient matches' : 'patients '
              'match'} the filters below.',
      method: <String>[
        'The filters shown were applied to the register on this device.',
        if (medication != null)
          'A medicine matches on the start of its name, so "$medication" also '
              'finds "$medication 5mg". Only medicines marked active count — a '
              'stopped prescription does not.',
        if (problem != null)
          'Only problems marked active count. A resolved problem does not.',
        if (allergy != null)
          'Only allergies marked active count.',
        if (ageBand != null)
          'Age is worked out from the recorded date of birth as at today. A '
              'patient with no date of birth recorded cannot be age-filtered '
              'and is left out.',
        if (notSeenSince != null)
          'Patients never seen at all are included, because someone registered '
              'and never followed up is exactly who this is meant to surface.',
        'No SQL was generated for this question. The filters map onto one '
            'hand-written, tested query — a model may choose the filters, but '
            'it never writes the query.',
      ],
      derivation: <ExplainRow>[
        for (final part in describe()) ExplainRow(label: part, value: ''),
        if (resultCount != null)
          ExplainRow(label: 'Matches', value: '$resultCount'),
      ],
      confidence: ExplainConfidence.measured,
      source: 'This device\'s register',
      caveat: 'It can only find what has been recorded in structured form. A '
          'drug written into the free text of a note but never added to the '
          'medication list will not appear here, and neither will a diagnosis '
          'that was never added to the problem list. Treat a recall list as a '
          'starting point, not as proof that nobody was missed.',
    );
  }
}
