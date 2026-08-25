import 'cohort_query.dart';
import '../../clinical/insights/note_intelligence.dart';

/// A query the router believes was asked, with what it matched on.
class RoutedQuery {
  const RoutedQuery({
    required this.query,
    required this.matched,
    required this.confidence,
  });

  final CohortQuery query;

  /// The words that produced each filter, so a mis-read question is visible
  /// rather than silent.
  final List<String> matched;

  /// 0–1. Low means "this is a guess, check the filters".
  final double confidence;
}

/// Maps a typed question onto filters — never onto SQL.
///
/// The distinction is the entire safety argument. Generating SQL from language
/// puts an unreviewable step between the question and the answer: a recall list
/// missing three patients is indistinguishable from a correct one, and there is
/// no second reader, because the whole point is that the clinician could not
/// run the query themselves.
///
/// Choosing among filters that a human wrote is a different, much easier and
/// much safer problem. Everything below is dictionary and pattern matching —
/// no model, instant, offline, and identical on every device. When a small
/// language model is installed it plugs in *beside* this as a second router for
/// phrasings the patterns miss, and it is held to the same contract: it returns
/// a [CohortQuery], never a string of SQL.
abstract final class QueryRouter {
  static RoutedQuery? route(String question, {DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    final text = _normalise(question);
    if (text.isEmpty) return null;

    final matched = <String>[];
    var query = CohortQuery(
      kind: _kindFor(text),
      entity: _entityFor(text),
    );
    if (query.entity != QueryEntity.patients) {
      matched.add('${query.entity.label.toLowerCase()} table');
    }

    // --- Name -------------------------------------------------------------
    // The most common thing a front desk needs, and the clearest gap in the
    // first vocabulary: it was built around clinical questions and had no way
    // to express "the Aryals" or "someone beginning with A".
    if (_nameFilter(text) case final name?) {
      query = switch (name.$1) {
        _NameMatch.prefix => query.copyWith(nameStartsWith: name.$2),
        _NameMatch.contains => query.copyWith(nameContains: name.$2),
      };
      matched.add(
        name.$1 == _NameMatch.prefix
            ? 'name starting with "${name.$2}"'
            : 'name containing "${name.$2}"',
      );
    }

    // --- MRN --------------------------------------------------------------
    if (RegExp(r'\b(?:mrn|record (?:number|no\.?))\s*#?\s*(\d{3,10})\b')
        .firstMatch(text) case final match?) {
      query = query.copyWith(mrn: match.group(1));
      matched.add('MRN ${match.group(1)}');
    }

    // --- Appointment status ------------------------------------------------
    if (query.entity == QueryEntity.appointments) {
      if (_appointmentStatus(text) case final status?) {
        query = query.copyWith(appointmentStatus: status.$1);
        matched.add(status.$2);
      }
    }

    // --- Unfinished charting ----------------------------------------------
    if (query.entity == QueryEntity.notes &&
        RegExp(r'\bunsigned\b|\bdrafts?\b|\bunfinished\b|\bincomplete\b')
            .hasMatch(text)) {
      query = query.copyWith(noteStatus: 'draft');
      matched.add('unsigned');
    }

    // --- Observation thresholds -------------------------------------------
    // "news2 above 5", "bp over 140" — the numbers a deterioration sweep is
    // actually about, and the reason a vitals table is worth reaching at all.
    if (_threshold(text, r'news ?2?|early warning|score') case final score?) {
      query = query.copyWith(
        news2AtLeast: score,
        entity: QueryEntity.vitals,
      );
      matched.add('early warning score $score or more');
    }
    if (_threshold(text, r'systolic|blood pressure|bp') case final systolic?) {
      query = query.copyWith(
        systolicAtLeast: systolic,
        entity: QueryEntity.vitals,
      );
      matched.add('systolic $systolic or more');
    }
    if (RegExp(r'\babnormal\b|\bout of range\b|\bflagged\b|\bderanged\b')
        .hasMatch(text)) {
      query = query.copyWith(
        abnormalOnly: true,
        entity: QueryEntity.vitals,
      );
      matched.add('abnormal observations');
    }

    // --- Recency -----------------------------------------------------------
    // "latest patients", "last 5 visits", "most recent notes". Ordinary
    // phrasing that produced nothing at all before, because the vocabulary was
    // built around filters and had no way to express "newest".
    if (_recency(text) case final recent?) {
      query = query.copyWith(mostRecent: recent.$1);
      matched.add(recent.$2);
    }

    // --- File kind ---------------------------------------------------------
    if (query.entity == QueryEntity.files) {
      if (_fileKind(text) case final kind?) {
        query = query.copyWith(fileKind: kind.$1);
        matched.add(kind.$2);
      }
    }

    // --- Medication -------------------------------------------------------
    for (final drug in _drugs) {
      if (!RegExp(r'\b' + RegExp.escape(drug) + r'\b').hasMatch(text)) continue;
      // "allergic to penicillin" is an allergy question, not a drug list.
      if (_allergyPhrasing.hasMatch(text)) {
        query = query.copyWith(allergy: drug, kind: CohortQueryKind.recall);
        matched.add('allergy to "$drug"');
      } else {
        query = query.copyWith(medication: drug, kind: CohortQueryKind.recall);
        matched.add('medicine "$drug"');
      }
      break;
    }

    // --- Problem ----------------------------------------------------------
    if (query.problem == null) {
      for (final entry in _problems.entries) {
        // `s?` before the boundary, because people ask about "diabetics" and
        // "asthmatics" rather than about "diabetes". Without it the trailing
        // word boundary cannot match before the plural and the whole question
        // silently loses its condition filter.
        if (!RegExp(r'\b' + entry.key + r's?\b').hasMatch(text)) continue;
        query = query.copyWith(problem: entry.value);
        matched.add('condition "${entry.value}"');
        break;
      }
    }

    // --- Age --------------------------------------------------------------
    if (_bandFor(text) case final band?) {
      query = query.copyWith(ageBand: band.$1);
      matched.add('age ${band.$1.label.toLowerCase()} (${band.$2})');
    }

    // --- Sex --------------------------------------------------------------
    if (RegExp(r'\b(女|women|female|girls?)\b').hasMatch(text)) {
      query = query.copyWith(sexAtBirth: 'female');
      matched.add('female');
    } else if (RegExp(r'\b(men|male|boys?)\b').hasMatch(text)) {
      query = query.copyWith(sexAtBirth: 'male');
      matched.add('male');
    }

    // --- Time -------------------------------------------------------------
    if (_notSeenSince(text, now) case final since?) {
      query = query.copyWith(
        notSeenSince: since.$1,
        kind: CohortQueryKind.overdue,
      );
      matched.add('not seen ${since.$2}');
    } else if (_period(text, now) case final period?) {
      query = query.copyWith(periodFrom: period.$1, periodTo: period.$2);
      matched.add('during ${period.$3}');
    }

    // A bare period on a non-patient table is a "how many" question even
    // without the words: "appointments this month" wants a number.
    if (query.kind == CohortQueryKind.recall &&
        query.entity != QueryEntity.patients &&
        query.periodFrom != null) {
      query = query.copyWith(kind: CohortQueryKind.activity);
    }

    // --- Whole table -------------------------------------------------------
    // Checked before the free-text fallback, not after. "Every single patient"
    // is a request for the register, and left to the fallback the word
    // "single" becomes a search term and the question quietly turns into
    // something else.
    if (matched.isEmpty && _isWholeTable(text)) {
      return RoutedQuery(
        query: query.copyWith(
          kind: _kindFor(text) == CohortQueryKind.activity
              ? CohortQueryKind.activity
              : CohortQueryKind.recall,
        ),
        matched: <String>['every ${query.entity.noun}'],
        confidence: 1,
      );
    }

    // --- Free text ---------------------------------------------------------
    // Whatever is left that looks like a word worth searching for. This is the
    // catch-all that turns "entries mentioning coffee or tea" into a real
    // search instead of a shrug: the structured vocabulary cannot know every
    // word that might appear in a note, and refusing everything it does not
    // recognise makes the search useless for the half of clinical information
    // that only exists as prose.
    if (matched.isEmpty || query.isEmpty) {
      final terms = _freeTextTerms(text);
      if (terms.isNotEmpty) {
        query = query.copyWith(anyTextOf: terms);
        matched.add(
          'text mentioning ${terms.map((t) => '"$t"').join(' or ')}',
        );
      }
    }

    // Nothing structured, and nothing worth searching prose for either.
    if (matched.isEmpty) return null;

    // Confidence is simply how much of the question was accounted for. A
    // question that produced one filter out of many words is a guess, and the
    // UI says so rather than presenting it as understood.
    final words = text.split(RegExp(r'\s+')).length;
    final confidence = (matched.length / (words / 3)).clamp(0.25, 1.0);

    return RoutedQuery(
      query: query,
      matched: matched,
      confidence: confidence.toDouble(),
    );
  }

  /// Which table the question is about, from the words that name it.
  ///
  /// The word lists live on [QueryEntity] rather than here, so the guide that
  /// teaches the vocabulary and the matcher that implements it cannot drift
  /// apart — a phrase the guide advertises is a phrase the router matches.
  static QueryEntity _entityFor(String text) {
    // Order is deliberate. Appointments come before visits because "did not
    // attend" is about a booking and contains no word naming a consultation.
    // Visits come last because their words are the most generic — "seen" would
    // otherwise capture questions that named a more specific table.
    for (final entity in <QueryEntity>[
      QueryEntity.appointments,
      QueryEntity.vitals,
      QueryEntity.notes,
      QueryEntity.files,
      QueryEntity.visits,
    ]) {
      for (final word in entity.triggerWords) {
        // `s?` before the boundary: people say "no shows" and "bookings", and
        // without it the trailing boundary cannot match past the plural.
        if (RegExp(r'\b' + RegExp.escape(word) + r's?\b').hasMatch(text)) {
          return entity;
        }
      }
    }
    return QueryEntity.patients;
  }

  /// "above 5", "over 140", "more than 8", ">= 5" following a named measure.
  static int? _threshold(String text, String measure) {
    final match = RegExp(
      '\\b(?:$measure)\\b[^.\n]{0,18}?'
      r'(?:above|over|greater than|more than|at least|>=?|of)\s*(\d{1,3})\b',
    ).firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// "latest", "most recent", "last 5", "newest 10".
  static (int, String)? _recency(String text) {
    final counted = RegExp(
      r'\b(?:latest|last|newest|most recent|recent)\s+(\d{1,3})\b',
    ).firstMatch(text);
    if (counted != null) {
      final n = int.tryParse(counted.group(1)!);
      if (n != null && n > 0) return (n, 'the $n most recent');
    }

    // A bare "latest" with no number. Ten is what a person means by "the
    // latest ones" — enough to scan, few enough to be a shortlist.
    if (RegExp(r'\b(?:latest|newest|most recent|recently added|'
            r'recently registered)\b')
        .hasMatch(text)) {
      return (_defaultRecent, 'the $_defaultRecent most recent');
    }
    return null;
  }

  static const int _defaultRecent = 10;

  /// Words worth searching the prose for, once the structured vocabulary has
  /// taken what it recognises.
  ///
  /// Everything that carries no meaning on its own is stripped first —
  /// otherwise "show me entries about coffee" would search for "show", "me"
  /// and "entries" as well, and match every record in the database.
  static List<String> _freeTextTerms(String text) {
    final quoted = RegExp(r'[\x27"]([^\x27"]{2,40})[\x27"]')
        .allMatches(text)
        .map((m) => m.group(1)!.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    // An explicit quotation is unambiguous; take it and look no further.
    if (quoted.isNotEmpty) return quoted.take(4).toList();

    final words = text
        .split(RegExp(r'[^a-z0-9\-]+'))
        .where((word) => word.length >= 3)
        .where((word) => !_stopWords.contains(word))
        .toList();

    if (words.isEmpty) return const <String>[];

    // "coffee or tea" is one filter with two terms; "coffee and tea" is
    // treated the same way here, because a record mentioning either is worth
    // showing and the reader can tell them apart from the excerpt.
    return words.take(4).toList();
  }

  /// Words that would match everything and mean nothing.
  static const Set<String> _stopWords = <String>{
    'the', 'and', 'or', 'with', 'without', 'for', 'from', 'into', 'onto',
    'about', 'that', 'this', 'these', 'those', 'there', 'their', 'them',
    'they', 'have', 'has', 'had', 'was', 'were', 'been', 'being', 'are',
    'any', 'all', 'every', 'each', 'some', 'many', 'much', 'more', 'most',
    'who', 'whom', 'whose', 'what', 'when', 'where', 'which', 'why', 'how',
    'show', 'find', 'list', 'give', 'get', 'see', 'look', 'search', 'tell',
    'entries', 'entry', 'record', 'records', 'result', 'results', 'data',
    'please', 'need', 'want', 'would', 'could', 'should', 'can', 'may',
    'mention', 'mentions', 'mentioning', 'mentioned', 'containing',
    'contains', 'contain', 'including', 'include', 'includes', 'anything',
    'something', 'everything', 'also', 'too', 'only', 'just', 'other',
    'others', 'like', 'such', 'than', 'then', 'over', 'under', 'above',
    'below', 'between', 'during', 'before', 'after', 'while', 'because',
    'patient', 'patients', 'people', 'person', 'persons',
  };

  static (String, String)? _fileKind(String text) {
    if (RegExp(r'\bphotos?\b|\bimages?\b|\bpictures?\b').hasMatch(text)) {
      return ('photo', 'photos');
    }
    if (RegExp(r'\brecordings?\b|\baudio\b|\bvoice notes?\b')
        .hasMatch(text)) {
      return ('audio', 'recordings');
    }
    if (RegExp(r'\bdocuments?\b|\bpdfs?\b|\bscans?\b').hasMatch(text)) {
      return ('document', 'documents');
    }
    return null;
  }

  static (String, String)? _appointmentStatus(String text) {
    if (RegExp(r'\bcancell?ed\b').hasMatch(text)) {
      return ('cancelled', 'cancelled');
    }
    if (RegExp(r'\bno[- ]?shows?\b|\bdid not attend\b|\bdna\b|\bmissed\b')
        .hasMatch(text)) {
      return ('noShow', 'did not attend');
    }
    if (RegExp(r'\bcompleted\b|\battended\b').hasMatch(text)) {
      return ('completed', 'completed');
    }
    if (RegExp(r'\bwaiting\b|\barrived\b').hasMatch(text)) {
      return ('arrived', 'arrived and waiting');
    }
    if (RegExp(r'\bupcoming\b|\bbooked\b|\bscheduled\b').hasMatch(text)) {
      return ('scheduled', 'still scheduled');
    }
    return null;
  }

  /// "name starting with A", "surname Aryal", "called Sita".
  static (_NameMatch, String)? _nameFilter(String text) {
    final prefix = RegExp(
      r'\b(?:names?|surname|family name|last name|first name|given name)\b'
      r'[^.\n]{0,24}?\b(?:start(?:s|ing)?|begin(?:s|ning)?)\b'
      // The connecting word has to be consumed explicitly. Left to a lazy
      // wildcard, the capture group lands on "with" and every such question
      // silently searches for patients named With.
      r'\s*(?:with|from|the letter|letter)?\s*'
      r'[\x27"]?([a-z][a-z\-\x27]*)',
    ).firstMatch(text);
    if (prefix != null) return (_NameMatch.prefix, _titleCase(prefix.group(1)!));

    // "with A" / "letter A" — a bare initial, which is how the request is
    // usually actually phrased at a desk.
    final initial = RegExp(
      r'\b(?:name|surname|family name|last name)\b[^.\n]{0,20}?'
      r'\b(?:with|letter)\s+([a-z])\b',
    ).firstMatch(text);
    if (initial != null) {
      return (_NameMatch.prefix, initial.group(1)!.toUpperCase());
    }

    final named = RegExp(
      r'\b(?:called|named|surname|family name|last name)\s+'
      r'([a-z][a-z\-\x27]{1,})\b',
    ).firstMatch(text);
    if (named != null) {
      return (_NameMatch.contains, _titleCase(named.group(1)!));
    }
    return null;
  }

  static String _titleCase(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  /// Strips the words people wrap a question in.
  ///
  /// Nobody types a query the way a parser wants one. "Can you show me all the
  /// patients please" and "patients" are the same request, and a matcher that
  /// only handles the second is a matcher people learn to distrust — they get a
  /// result once, cannot reproduce it, and stop using the feature.
  ///
  /// Only genuinely empty words are removed. Anything that could carry meaning
  /// — a quantifier like "no", a negation, a number — is left alone, because
  /// discarding one of those would change the question rather than tidy it.
  static String _normalise(String question) {
    var text = question.toLowerCase().trim();

    // Politeness and framing, which appear at the start and mean nothing.
    text = text.replaceAll(
      RegExp(
        r'\b(?:can you|could you|would you|please|kindly|i want to|'
        r'i need to|i would like to|show me|give me|tell me|find me|get me|'
        r'let me see|display|fetch|search for|look up|look for|pull up|'
        r'list out|list me|how about|what about|hey|hi)\b',
      ),
      ' ',
    );

    // Filler that survives mid-sentence.
    text = text.replaceAll(
      RegExp(r'\b(?:just|simply|actually|really|basically|kind of|sort of|'
          r'the whole|entire|complete|full)\b'),
      ' ',
    );

    // Punctuation people type but the matcher does not want. Apostrophes and
    // hyphens stay: they are inside names and inside "haven't".
    text = text.replaceAll(RegExp(r'[?!.,;:]+'), ' ');

    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// True when what is left, once quantifiers and table words are removed, is
  /// nothing — i.e. the question asks for the whole table and no more.
  ///
  /// Deciding it by subtraction rather than by matching "all" is what keeps
  /// "all the weather" from returning the entire register: "weather" survives
  /// the subtraction, so the question is correctly not understood.
  static bool _isWholeTable(String text) {
    var rest = text.replaceAll(
      RegExp(r'\b(?:all|every|each|any|everyone|everybody|anyone|anybody|'
          r'everything|list|the|a|an|of|in|on|our|my|we|us|have|has|there|'
          r'is|are|registered|records?|total)\b'),
      ' ',
    );

    for (final entity in QueryEntity.values) {
      for (final word in entity.triggerWords) {
        rest = rest.replaceAll(
          RegExp(r'\b' + RegExp.escape(word) + r's?\b'),
          ' ',
        );
      }
    }
    rest = rest.replaceAll(
      RegExp(r'\b(?:how many|count|number|single|people|persons?)\b'),
      ' ',
    );

    return rest.replaceAll(RegExp(r'\s+'), ' ').trim().isEmpty;
  }

  static CohortQueryKind _kindFor(String text) {
    if (RegExp(r'\bhow many\b|\bcount\b|\btotal\b|\bnumber of\b')
        .hasMatch(text)) {
      return CohortQueryKind.activity;
    }
    // "missed" alone is ambiguous — a missed appointment is a status, a
    // missed review is an overdue patient — so it only counts here alongside a
    // word about being seen.
    if (RegExp(r'\boverdue\b|\bnot seen\b|\bhaven.?t (been )?seen\b|'
            r'\blapsed\b|\bdue for\b|\bmissed (?:their )?(?:review|reviews|'
            r'follow[- ]?ups?)\b')
        .hasMatch(text)) {
      return CohortQueryKind.overdue;
    }
    return CohortQueryKind.recall;
  }

  static final RegExp _allergyPhrasing =
      RegExp(r'\ballerg(y|ic|ies)\b|\breaction to\b|\bintoleran');

  /// "not seen in 6 months" → the cutoff date, plus how to say it back.
  static (DateTime, String)? _notSeenSince(String text, DateTime now) {
    final match = RegExp(
      r'\b(?:not seen|no visit|nothing|haven.?t (?:been )?seen|last seen)\b'
      r'[^.\n]{0,20}?\b(\d{1,3})\s*(day|week|month|year)s?\b',
    ).firstMatch(text);
    if (match != null) {
      final amount = int.parse(match.group(1)!);
      final unit = match.group(2)!;
      return (
        _minus(now, amount, unit),
        'in $amount $unit${amount == 1 ? '' : 's'}',
      );
    }

    // "overdue" with no interval — six months is the conventional default for
    // a chronic-disease review, and the filter line says so explicitly.
    if (RegExp(r'\boverdue\b|\bdue for (a )?review\b').hasMatch(text)) {
      return (_minus(now, 6, 'month'), 'in 6 months (assumed)');
    }
    return null;
  }

  static DateTime _minus(DateTime from, int amount, String unit) {
    return switch (unit) {
      'day' => from.subtract(Duration(days: amount)),
      'week' => from.subtract(Duration(days: amount * 7)),
      'month' => DateTime(from.year, from.month - amount, from.day),
      _ => DateTime(from.year - amount, from.month, from.day),
    };
  }

  /// "last month", "this week", "in the last 30 days" → a date range.
  static (DateTime, DateTime, String)? _period(String text, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);

    if (RegExp(r'\btoday\b').hasMatch(text)) {
      return (today, today.add(const Duration(days: 1)), 'today');
    }
    if (RegExp(r'\bthis week\b').hasMatch(text)) {
      final start = today.subtract(Duration(days: today.weekday - 1));
      return (start, start.add(const Duration(days: 7)), 'this week');
    }
    if (RegExp(r'\blast week\b').hasMatch(text)) {
      final thisWeek = today.subtract(Duration(days: today.weekday - 1));
      final start = thisWeek.subtract(const Duration(days: 7));
      return (start, thisWeek, 'last week');
    }
    if (RegExp(r'\bthis month\b').hasMatch(text)) {
      final start = DateTime(now.year, now.month);
      return (start, DateTime(now.year, now.month + 1), 'this month');
    }
    if (RegExp(r'\blast month\b').hasMatch(text)) {
      final start = DateTime(now.year, now.month - 1);
      return (start, DateTime(now.year, now.month), 'last month');
    }
    if (RegExp(r'\bthis year\b').hasMatch(text)) {
      return (DateTime(now.year), DateTime(now.year + 1), 'this year');
    }

    final window = RegExp(
      r'\b(?:last|past|previous)\s+(\d{1,3})\s*(day|week|month|year)s?\b',
    ).firstMatch(text);
    if (window != null) {
      final amount = int.parse(window.group(1)!);
      final unit = window.group(2)!;
      return (
        _minus(today, amount, unit),
        today.add(const Duration(days: 1)),
        'the last $amount $unit${amount == 1 ? '' : 's'}',
      );
    }
    return null;
  }

  static (AgeBand, String)? _bandFor(String text) {
    if (RegExp(r'\bunder ?(1|one)\b|\binfants?\b|\bbabies\b|\bbaby\b')
        .hasMatch(text)) {
      return (AgeBand.under1, 'infants');
    }
    if (RegExp(r'\bunder ?(5|five)s?\b|\bunder-?fives?\b').hasMatch(text)) {
      return (AgeBand.under5, 'under fives');
    }
    if (RegExp(r'\bchildren\b|\bkids\b|\bpaediatric\b|\bpediatric\b')
        .hasMatch(text)) {
      return (AgeBand.child, 'children');
    }
    if (RegExp(r'\badolescents?\b|\bteenagers?\b|\bteens\b').hasMatch(text)) {
      return (AgeBand.adolescent, 'adolescents');
    }
    if (RegExp(r'\bover ?(65|sixty-?five)\b|\belderly\b|\bolder adults?\b')
        .hasMatch(text)) {
      return (AgeBand.over65, 'over 65s');
    }
    if (RegExp(r'\badults?\b').hasMatch(text)) return (AgeBand.adult, 'adults');
    return null;
  }

  /// Drug and condition vocabularies are shared with the note extractor rather
  /// than duplicated, so a term the app can pull out of a note is a term it can
  /// also be asked about. Two lists would drift apart within a release.
  static List<String> get _drugs => NoteIntelligence.knownMedications;

  static Map<String, String> get _problems => NoteIntelligence.knownProblems;

  /// Example questions for the empty state. Every one of these is covered by
  /// the patterns above and by a test, so the UI never suggests something that
  /// does not work.
  static const List<String> examples = <String>[
    'patients with name starting with A',
    'appointments this month',
    'everyone on warfarin',
    'unsigned notes',
    'observations with news2 above 5',
    'patients allergic to penicillin',
    'diabetics not seen in 6 months',
    'appointments that were cancelled this month',
    'photos from last week',
    'how many visits last month',
    'under fives with pneumonia this month',
  ];
}

enum _NameMatch { prefix, contains }
