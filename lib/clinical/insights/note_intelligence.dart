import '../explanations.dart';

/// Something found in note text that probably belongs on the structured chart.
class ExtractedTerm {
  const ExtractedTerm({
    required this.text,
    required this.kind,
    required this.matchedPhrase,
    required this.offset,
  });

  /// The candidate as it should be filed — normalised, not the raw match.
  final String text;
  final ExtractedTermKind kind;

  /// The words in the note that triggered it, so the clinician can see why.
  final String matchedPhrase;
  final int offset;
}

enum ExtractedTermKind { problem, medication, allergy, followUp, redFlag }

extension ExtractedTermKindX on ExtractedTermKind {
  String get label => switch (this) {
        ExtractedTermKind.problem => 'Problem',
        ExtractedTermKind.medication => 'Medication',
        ExtractedTermKind.allergy => 'Allergy',
        ExtractedTermKind.followUp => 'Follow-up',
        ExtractedTermKind.redFlag => 'Red flag',
      };
}

class FollowUpMention {
  const FollowUpMention({
    required this.phrase,
    required this.interval,
  });

  final String phrase;
  final Duration interval;
}

/// Reads free-text note content and offers structured entries for it.
///
/// The problem this solves is real and boring: a clinician writes "started on
/// amlodipine 5mg" in the plan, and the medication list still says nothing.
/// The structured chart drifts away from the narrative, and six months later
/// the medication list is not trustworthy enough to prescribe against.
///
/// Dictionary and pattern matching, not inference. That choice is the point:
/// it runs instantly, offline, on any device, and its behaviour is exactly
/// predictable — a clinician can learn what it will and will not catch, which
/// they cannot do with a model that is right most of the time for reasons
/// nobody can see. **Everything it produces is a suggestion requiring a tap to
/// accept.** Nothing is ever written to a chart from parsed text.
abstract final class NoteIntelligence {
  static List<ExtractedTerm> extract(String note) {
    if (note.trim().isEmpty) return const <ExtractedTerm>[];
    final lower = note.toLowerCase();
    final found = <ExtractedTerm>[];
    final seen = <String>{};

    void add(ExtractedTerm term) {
      final key = '${term.kind.name}:${term.text.toLowerCase()}';
      if (seen.add(key)) found.add(term);
    }

    // --- Medications ------------------------------------------------------
    // Matched with an optional dose, because "amlodipine" and "amlodipine 5mg"
    // should both be offered but the second saves retyping.
    for (final drug in _medications) {
      final pattern = RegExp(
        r'\b' + RegExp.escape(drug) +
            r'\b(\s*\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|units?|iu)\b)?',
        caseSensitive: false,
      );
      final matches = pattern.allMatches(lower).toList();
      if (matches.isEmpty) continue;

      // A drug written once with a dose and again without it is one
      // prescription, and the mention carrying the dose is the useful one.
      // Offering both would make the clinician delete a suggestion to accept
      // its twin.
      final best = matches.firstWhere(
        (m) => m.group(1) != null,
        orElse: () => matches.first,
      );
      final dose = best.group(1)?.trim();
      add(
        ExtractedTerm(
          text: dose == null ? _titleCase(drug) : '${_titleCase(drug)} $dose',
          kind: ExtractedTermKind.medication,
          matchedPhrase: note.substring(best.start, best.end).trim(),
          offset: best.start,
        ),
      );
    }

    // --- Allergies --------------------------------------------------------
    // Only inside an explicit allergy phrasing. Matching a drug name near the
    // word "allergy" anywhere in a note produces false allergies, and a false
    // allergy entry causes a real harm: it removes a treatment option, often
    // permanently, because nobody ever feels safe deleting one.
    final allergyPattern = RegExp(
      r'\b(?:allergic\s+to|allergy\s+to|reaction\s+to|intolerant\s+of|'
      r'intolerance\s+to)\s+([a-z][a-z\s\-]{2,40})',
      caseSensitive: false,
    );
    for (final match in allergyPattern.allMatches(lower)) {
      final substance = _firstClause(match.group(1)!);
      if (substance.isEmpty) continue;
      add(
        ExtractedTerm(
          text: _titleCase(substance),
          kind: ExtractedTermKind.allergy,
          matchedPhrase: note.substring(match.start, match.end).trim(),
          offset: match.start,
        ),
      );
    }

    // --- Problems ---------------------------------------------------------
    for (final entry in _problems.entries) {
      final pattern = RegExp(r'\b' + entry.key + r'\b', caseSensitive: false);
      final match = pattern.firstMatch(lower);
      if (match == null) continue;
      // "no evidence of pneumonia" and "ruled out DVT" are the opposite of a
      // diagnosis, and offering them as problems is worse than offering
      // nothing.
      if (_isNegated(lower, match.start)) continue;
      add(
        ExtractedTerm(
          text: entry.value,
          kind: ExtractedTermKind.problem,
          matchedPhrase: note.substring(match.start, match.end).trim(),
          offset: match.start,
        ),
      );
    }

    // --- Red flags --------------------------------------------------------
    for (final entry in _redFlags.entries) {
      final pattern = RegExp(r'\b' + entry.key + r'\b', caseSensitive: false);
      final match = pattern.firstMatch(lower);
      if (match == null) continue;
      if (_isNegated(lower, match.start)) continue;
      add(
        ExtractedTerm(
          text: entry.value,
          kind: ExtractedTermKind.redFlag,
          matchedPhrase: note.substring(match.start, match.end).trim(),
          offset: match.start,
        ),
      );
    }

    found.sort((a, b) => a.offset.compareTo(b.offset));
    return found;
  }

  /// Finds "review in 2 weeks" and the like, so the follow-up date can be
  /// offered as a booking rather than left in prose nobody queries.
  static FollowUpMention? followUp(String note) {
    final pattern = RegExp(
      r'\b(?:review|follow[\s-]?up|recheck|return|see|reassess|rv)\b'
      r'[^.\n]{0,24}?\b(?:in|after)\s+'
      r'(\d{1,3})\s*(day|days|week|weeks|month|months|year|years)\b',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(note);
    if (match != null) {
      final amount = int.tryParse(match.group(1)!);
      if (amount != null && amount > 0) {
        return FollowUpMention(
          phrase: match.group(0)!.trim(),
          interval: _intervalFor(amount, match.group(2)!.toLowerCase()),
        );
      }
    }

    // "review tomorrow" / "review next week" — no number to parse.
    final relative = RegExp(
      r'\b(?:review|follow[\s-]?up|recheck|return|reassess)\b[^.\n]{0,20}?'
      r'\b(tomorrow|next\s+week|next\s+month)\b',
      caseSensitive: false,
    ).firstMatch(note);
    if (relative == null) return null;

    return FollowUpMention(
      phrase: relative.group(0)!.trim(),
      interval: switch (relative.group(1)!.toLowerCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      )) {
        'tomorrow' => const Duration(days: 1),
        'next week' => const Duration(days: 7),
        _ => const Duration(days: 30),
      },
    );
  }

  static Duration _intervalFor(int amount, String unit) {
    if (unit.startsWith('day')) return Duration(days: amount);
    if (unit.startsWith('week')) return Duration(days: amount * 7);
    if (unit.startsWith('month')) return Duration(days: amount * 30);
    return Duration(days: amount * 365);
  }

  /// Whether the occurrence of a term at [index] in [text] is denied by the
  /// words before it.
  ///
  /// Exposed because free-text search needs exactly the same judgement: a note
  /// reading "no history of warfarin" must not put that patient on a warfarin
  /// recall list, and re-implementing the check for the search would give two
  /// answers to one question.
  static bool isNegatedAt(String text, int index) =>
      _isNegated(text.toLowerCase(), index);

  /// True when the match sits inside a phrase that denies it.
  ///
  /// Looks back a bounded distance rather than parsing the sentence. It will
  /// miss elaborate constructions, and that is the acceptable direction: a
  /// missed suggestion costs a clinician nothing, whereas offering "chest pain"
  /// as a problem when the note says "denies chest pain" costs trust
  /// immediately.
  static bool _isNegated(String lower, int index) {
    final from = index < _negationWindow ? 0 : index - _negationWindow;
    final preceding = lower.substring(from, index);
    // A sentence boundary ends the negation's scope.
    final clause = preceding.split(RegExp(r'[.;\n]')).last;
    return _negations.any(clause.contains);
  }

  static const int _negationWindow = 40;

  static const List<String> _negations = <String>[
    'no ', 'not ', 'denies', 'denied', 'without', 'negative for',
    'ruled out', 'rule out', 'r/o ', 'absent', 'no evidence of',
    'unlikely', 'nil ', 'free of', 'resolved',
  ];

  static String _firstClause(String value) {
    final stop = RegExp(r'\b(?:and|with|but|which|causing|since|for)\b');
    final match = stop.firstMatch(value);
    final clause = match == null ? value : value.substring(0, match.start);
    return clause.trim().replaceAll(RegExp(r'[\s,]+$'), '');
  }

  static String _titleCase(String value) => value
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');

  /// The drug vocabulary, also used by the cohort query router so that a term
  /// the app can pull out of a note is a term it can be asked about. Two lists
  /// would drift apart within a release.
  static List<String> get knownMedications => _medications;

  /// The condition vocabulary, shared for the same reason.
  static Map<String, String> get knownProblems => _problems;

  /// Common generics, weighted toward primary care and the WHO essential
  /// medicines list. Not a formulary and not a dosing reference — its only job
  /// is to notice that a drug was mentioned.
  static const List<String> _medications = <String>[
    'paracetamol', 'acetaminophen', 'ibuprofen', 'diclofenac', 'aspirin',
    'naproxen', 'tramadol', 'morphine', 'codeine',
    'amoxicillin', 'amoxicillin-clavulanate', 'co-amoxiclav', 'azithromycin',
    'ciprofloxacin', 'ceftriaxone', 'cefixime', 'doxycycline', 'metronidazole',
    'nitrofurantoin', 'penicillin', 'flucloxacillin', 'clarithromycin',
    'gentamicin', 'cotrimoxazole', 'erythromycin',
    'amlodipine', 'lisinopril', 'enalapril', 'losartan', 'atenolol',
    'bisoprolol', 'metoprolol', 'propranolol', 'hydrochlorothiazide',
    'furosemide', 'spironolactone', 'atorvastatin', 'simvastatin',
    'metformin', 'glibenclamide', 'gliclazide', 'insulin', 'glimepiride',
    'salbutamol', 'beclometasone', 'prednisolone', 'dexamethasone',
    'hydrocortisone', 'montelukast',
    'omeprazole', 'ranitidine', 'famotidine', 'ondansetron', 'metoclopramide',
    'loperamide', 'oral rehydration salts', 'ors',
    'ferrous sulphate', 'folic acid', 'vitamin d', 'calcium carbonate',
    'zinc sulphate', 'vitamin a',
    'artemether-lumefantrine', 'artesunate', 'chloroquine', 'quinine',
    'albendazole', 'mebendazole', 'ivermectin', 'praziquantel',
    'isoniazid', 'rifampicin', 'pyrazinamide', 'ethambutol',
    'amitriptyline', 'fluoxetine', 'sertraline', 'diazepam', 'phenytoin',
    'carbamazepine', 'phenobarbital', 'levetiracetam', 'haloperidol',
    'levothyroxine', 'warfarin', 'clopidogrel', 'heparin', 'tranexamic acid',
    'oxytocin', 'magnesium sulphate', 'misoprostol', 'medroxyprogesterone',
    'ceftazidime', 'chlorphenamine', 'cetirizine', 'loratadine',
    'adrenaline', 'epinephrine', 'atropine', 'naloxone', 'hydralazine',
    'nifedipine', 'methyldopa', 'labetalol', 'digoxin', 'allopurinol',
  ];

  /// Phrase to the term it should be filed as. Keys are regular-expression
  /// fragments so spelling variants collapse to one entry.
  static const Map<String, String> _problems = <String, String>{
    r'hypertensi(?:on|ve)': 'Hypertension',
    r'diabet(?:es|ic)(?:\s+mellitus)?': 'Diabetes mellitus',
    r'asthma(?:tic)?': 'Asthma',
    r'copd|chronic obstructive': 'COPD',
    r'pneumonia': 'Pneumonia',
    r'tuberculosis|\btb\b': 'Tuberculosis',
    r'malaria': 'Malaria',
    r'anaemia|anemia': 'Anaemia',
    r'urinary tract infection|\buti\b': 'Urinary tract infection',
    r'gastroenteritis': 'Gastroenteritis',
    r'migraine': 'Migraine',
    r'epilepsy|seizure disorder': 'Epilepsy',
    r'depression|depressive': 'Depression',
    r'anxiety disorder': 'Anxiety disorder',
    r'osteoarthritis': 'Osteoarthritis',
    r'rheumatoid arthritis': 'Rheumatoid arthritis',
    r'hypothyroid(?:ism)?': 'Hypothyroidism',
    r'hyperthyroid(?:ism)?': 'Hyperthyroidism',
    r'chronic kidney disease|\bckd\b': 'Chronic kidney disease',
    r'heart failure|\bccf\b': 'Heart failure',
    r'atrial fibrillation|\bafib?\b': 'Atrial fibrillation',
    r'dengue': 'Dengue fever',
    r'typhoid|enteric fever': 'Typhoid fever',
    r'hepatitis\s*[abce]?': 'Hepatitis',
    r'gastritis': 'Gastritis',
    r'peptic ulcer': 'Peptic ulcer disease',
    r'cellulitis': 'Cellulitis',
    r'otitis media': 'Otitis media',
    r'sinusitis': 'Sinusitis',
    r'tonsillitis|pharyngitis': 'Pharyngitis',
    r'conjunctivitis': 'Conjunctivitis',
    r'eczema|atopic dermatitis': 'Eczema',
    r'scabies': 'Scabies',
    r'malnutrition': 'Malnutrition',
    r'pre[\s-]?eclampsia': 'Pre-eclampsia',
    r'sickle cell': 'Sickle cell disease',
    r'\bhiv\b': 'HIV infection',
  };

  /// Phrases that should stop a clinician mid-note. Surfaced separately and
  /// never as a "problem" — the point is to prompt, not to diagnose.
  static const Map<String, String> _redFlags = <String, String>{
    r'chest pain': 'Chest pain — consider cardiac cause',
    r'crushing (?:central )?chest': 'Crushing chest pain',
    r'short(?:ness)? of breath|dyspnoea|dyspnea|breathless':
        'Breathlessness',
    r'haemoptysis|hemoptysis|coughing (?:up )?blood': 'Coughing blood',
    r'haematemesis|hematemesis|vomiting blood': 'Vomiting blood',
    r'melaena|melena|black (?:tarry )?stool': 'Melaena',
    r'per rectal bleed|rectal bleeding|\bpr bleed': 'Rectal bleeding',
    r'sudden (?:severe )?headache|thunderclap': 'Sudden severe headache',
    r'neck stiffness|photophobia': 'Meningism',
    r'altered consciousness|unresponsive|confus(?:ed|ion)':
        'Altered consciousness',
    r'unintentional weight loss|weight loss': 'Weight loss',
    r'night sweats': 'Night sweats',
    r'suicidal|self[\s-]?harm': 'Suicidal ideation — assess risk',
    r'reduced fetal movement|no fetal movement': 'Reduced fetal movements',
    r'convulsion|fitting|seizure': 'Seizure',
    r'unable to (?:walk|weight bear)': 'Unable to weight bear',
  };

  static MetricExplanation explain(int suggestionCount) {
    return MetricExplanation(
      title: 'Suggestions from your note',
      summary: 'Terms found in the text that may belong on the structured '
          'chart. $suggestionCount found. Nothing is added until you tap it.',
      method: const <String>[
        'The note text is searched for medicine names from a list of common '
            'generics, together with any dose written beside them.',
        'Diagnoses and red-flag phrases are matched against a fixed list of '
            'terms and their common spellings.',
        'Anything preceded by a denial in the same clause — "no", "denies", '
            '"ruled out" — is discarded.',
        'An allergy is only offered when the text explicitly says so, such as '
            '"allergic to". A wrongly recorded allergy removes a treatment '
            'option, often permanently.',
        'A phrase like "review in 2 weeks" is turned into a date you can book '
            'from.',
      ],
      confidence: ExplainConfidence.heuristic,
      source: 'Fixed dictionary matching — this app. No model, no inference.',
      caveat: 'It only knows the words on its lists, so it will silently miss '
          'anything else — including whole categories such as procedures and '
          'most specialist drugs. It is a way to save typing, and never a '
          'check that a note is complete.',
    );
  }
}
