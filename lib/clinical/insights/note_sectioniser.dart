/// Which part of a SOAP note a sentence belongs in.
enum NoteSection { subjective, objective, assessment, plan }

extension NoteSectionX on NoteSection {
  String get key => name;

  String get label => switch (this) {
        NoteSection.subjective => 'Subjective',
        NoteSection.objective => 'Objective',
        NoteSection.assessment => 'Assessment',
        NoteSection.plan => 'Plan',
      };
}

/// One sentence of dictation, and where it was placed.
typedef SectionedSentence = ({
  int index,
  String text,
  NoteSection? section,
  int confidence,
});

/// Sorts dictated sentences into SOAP sections by clinical wording.
///
/// This is the app's own sort, and it runs whether or not a language model is
/// installed. That ordering is not a fallback grudgingly provided — it is the
/// same principle the rest of the assistant follows: the vocabulary of a
/// clinical note is small and conventional, so matching it is fast, offline,
/// identical on every device, and can show its working. "On examination"
/// introduces an objective finding in every clinic in the world; recognising
/// that needs a word list, not a model.
///
/// The model's role, when there is one, is to place the sentences this cannot
/// — and it does so by *choosing among these sentences*, never by writing
/// text. See `NoteDrafting`.
///
/// Nothing here rewrites a sentence. A sentence is placed or left alone.
abstract final class NoteSectioniser {
  /// Splits dictation into sentences, keeping them exactly as spoken.
  ///
  /// Newlines count as boundaries as well as full stops: dictated text often
  /// arrives with line breaks and no punctuation at all, and treating a
  /// paragraph as one sentence would make the whole sort a no-op.
  static List<String> sentences(String text) => text
      .split(RegExp(r'(?<=[.!?])\s+|\n+'))
      .map((sentence) => sentence.trim())
      .where((sentence) => sentence.isNotEmpty)
      .toList();

  /// Sorts every sentence, leaving the unrecognisable ones unplaced.
  static List<SectionedSentence> sort(String text) {
    final out = <SectionedSentence>[];
    final all = sentences(text);
    for (var i = 0; i < all.length; i++) {
      final scored = _score(all[i]);
      out.add((
        index: i,
        text: all[i],
        section: scored.section,
        confidence: scored.score,
      ));
    }
    return out;
  }

  /// A sentence's section and how strongly the wording says so, 0 when
  /// nothing matched.
  static ({NoteSection? section, int score}) _score(String sentence) {
    final text = sentence.toLowerCase();
    final scores = <NoteSection, int>{
      NoteSection.subjective: 0,
      NoteSection.objective: 0,
      NoteSection.assessment: 0,
      NoteSection.plan: 0,
    };

    for (final entry in _cues.entries) {
      for (final cue in entry.value) {
        if (cue.pattern.hasMatch(text)) {
          scores[entry.key] = scores[entry.key]! + cue.weight;
        }
      }
    }

    var best = NoteSection.subjective;
    var bestScore = 0;
    var tied = false;
    for (final entry in scores.entries) {
      if (entry.value > bestScore) {
        best = entry.key;
        bestScore = entry.value;
        tied = false;
      } else if (entry.value == bestScore && bestScore > 0) {
        tied = true;
      }
    }

    // A tie is not a placement. Two sections claiming a sentence equally
    // means the wording does not decide it, and guessing between them puts an
    // examination finding under History as often as not.
    if (bestScore == 0 || tied) return (section: null, score: 0);
    return (section: best, score: bestScore);
  }

  /// A cue and how much it counts.
  ///
  /// Weights, not booleans, because these overlap: "temperature 37.9" is an
  /// observation, but "reports a temperature at home" is history, and the
  /// stronger cue has to win rather than the first one checked.
  static final Map<NoteSection, List<({RegExp pattern, int weight})>> _cues =
      <NoteSection, List<({RegExp pattern, int weight})>>{
    NoteSection.subjective: <({RegExp pattern, int weight})>[
      (pattern: RegExp(r'\b(?:reports?|reported|complain(?:s|ing|ed)? of|'
          r'describes?|states?|says?|tells? me|mentions?)\b'), weight: 3),
      (pattern: RegExp(r'\b(?:denies|denied|no history of|nil of note)\b'),
          weight: 3),
      (pattern: RegExp(r'\bhistory of\b|\bpast medical\b|\bpmh\b'), weight: 2),
      (pattern: RegExp(r'\b(?:patient|he|she|they)\s+(?:has|had|have|feels?|'
          r'felt|noticed|been)\b'), weight: 2),
      (pattern: RegExp(r'\b(?:since|for the (?:last|past)|started|onset|'
          r'came on|began)\b'), weight: 2),
      (pattern: RegExp(r'\b(?:presenting|presents? with|c/o|complaint)\b'),
          weight: 3),
      (pattern: RegExp(r'\b(?:worse|better|worsening|improving) (?:at|when|'
          r'with|after)\b'), weight: 1),
      (pattern: RegExp(r'\b(?:smokes?|drinks?|lives? (?:with|alone)|works? as)'
          r'\b'), weight: 2),
    ],
    NoteSection.objective: <({RegExp pattern, int weight})>[
      (pattern: RegExp(r'\bon examination\b|\bo/e\b|\bexamination\b|'
          r'\bexamined\b'), weight: 4),
      (pattern: RegExp(r'\b(?:auscultation|palpation|percussion|inspection)\b'),
          weight: 4),
      (pattern: RegExp(r'\b(?:chest|abdomen|abdo|throat|ears?|eyes?|skin|'
          r'heart sounds?)\s+(?:is|are|was|were)?\s*(?:clear|soft|normal|'
          r'tender|nad)\b'), weight: 4),
      (pattern: RegExp(r'\b(?:bp|blood pressure|pulse|heart rate|temperature|'
          r'temp|sats?|saturations?|spo2|respiratory rate|rr|news2?|bmi|'
          r'weight|height|glucose|bm)\b'), weight: 3),
      (pattern: RegExp(r'\b(?:observations?|obs|vitals?|readings?)\b'),
          weight: 3),
      (pattern: RegExp(r'\b(?:no|nil)\s+(?:rash|swelling|tenderness|'
          r'lymphadenopathy|oedema|edema|murmur|wheeze|crackles)\b'),
          weight: 3),
      (pattern: RegExp(r'\b(?:x-?ray|bloods?|ecg|urinalysis|swab|result)s?\s+'
          r'(?:show|shows|showed|were|was|normal|clear)\b'), weight: 3),
      (pattern: RegExp(r'\b(?:looks?|appears?|alert|afebrile|febrile|'
          r'well|unwell)\b'), weight: 2),
    ],
    NoteSection.assessment: <({RegExp pattern, int weight})>[
      (pattern: RegExp(r'\b(?:likely|probable|probably|consistent with|'
          r'suggestive of|in keeping with|suspect|suspected)\b'), weight: 4),
      (pattern: RegExp(r'\b(?:impression|assessment|diagnosis|dx)\b'),
          weight: 4),
      (pattern: RegExp(r'\b(?:differential|rule out|exclude|cannot exclude|'
          r'r/o)\b'), weight: 3),
      (pattern: RegExp(r'\b(?:appears to be|seems to be|most likely)\b'),
          weight: 3),
      (pattern: RegExp(r'\b(?:stable|deteriorating|improving|resolved|'
          r'unchanged)\b'), weight: 1),
    ],
    NoteSection.plan: <({RegExp pattern, int weight})>[
      (pattern: RegExp(r'\b(?:prescribe[ds]?|start(?:ed|ing)?|commence|'
          r'give|given|continue|stop|increase|decrease|titrate)\b'),
          weight: 3),
      (pattern: RegExp(r'\b(?:review|follow[- ]?up|f/u|recall|see again|'
          r'return|come back|reassess)\b'), weight: 4),
      (pattern: RegExp(r'\b(?:refer|referral|admit|discharge|signpost)\b'),
          weight: 4),
      (pattern: RegExp(r'\b(?:advise[ds]?|advice|safety[- ]?net|'
          r'reassur(?:e|ed|ance)|counsell?ed|educated)\b'), weight: 3),
      (pattern: RegExp(r'\b(?:request|order|arrange|book|send for|check)\b'),
          weight: 3),
      (pattern: RegExp(r'\b(?:if|should)\b.*\b(?:worse|worsens|not improve|'
          r'no better|return|seek)\b'), weight: 3),
      // "paracetamol 500mg" and "paracetamol for fever" are both plans.
      (pattern: RegExp(r'\b\d+\s*(?:mg|mcg|ml|g|units?)\b'), weight: 3),
      (pattern: RegExp(r'\b(?:bd|tds|qds|od|prn|nocte|po|im|iv)\b'),
          weight: 3),
      (pattern: RegExp(r'\b(?:in|for)\s+(?:one|two|three|\d+)\s+'
          r'(?:day|days|week|weeks|month|months)\b'), weight: 2),
    ],
  };
}
