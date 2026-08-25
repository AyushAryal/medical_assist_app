import '../../core/utils/text_similarity.dart';

/// Colloquial phrasings mapped to questions the interpreters answer.
///
/// The grammars match structure; people type intent. "Who should I worry
/// about" has no superlative, no measure and no table word in it, and no
/// amount of grammar covers it — but it *is* a known question wearing
/// different words, and a dictionary of those is cheap, testable and honest
/// in a way a guess is not: the rewrite is recorded in the provenance trail,
/// so the answer always says which question it actually ran.
///
/// A test walks every canonical target through the full interpreter chain,
/// so an entry here can never point at a question the app stopped answering.
abstract final class Paraphrases {
  static const Map<String, String> _bank = <String, String>{
    // Risk and deterioration.
    'who should i worry about': 'riskiest patients',
    'who should i be worried about': 'riskiest patients',
    'anyone to worry about': 'riskiest patients',
    'who is getting worse': 'riskiest patients',
    'who is deteriorating': 'riskiest patients',
    'who needs attention': 'riskiest patients',
    'who is not doing well': 'riskiest patients',
    'sickest on the register': 'riskiest patients',

    // The day and the backlog.
    'what is on today': 'appointments today',
    'what does today look like': 'appointments today',
    'todays list': 'appointments today',
    'todays schedule': 'appointments today',
    'who is coming in today': 'appointments today',
    'charts to sign': 'unsigned notes',
    'notes to sign': 'unsigned notes',
    'unfinished paperwork': 'unsigned notes',
    'paperwork to finish': 'unsigned notes',

    // Falling out of care.
    'who have we lost track of': 'patients not seen in 6 months',
    'who has not been in for a while': 'patients not seen in 6 months',
    'lapsed patients': 'patients not seen in 6 months',

    // Activity.
    'how busy have we been': 'visits per week',
    'how busy are we': 'visits per week',
    'new faces': 'latest patients',
    'recently registered': 'latest patients',
  };

  /// The canonical question for a colloquial one, or null.
  ///
  /// Exact containment first, then a whole-utterance fuzzy match — high
  /// floor, because a wrong rewrite answers a question nobody asked and the
  /// rewrite line in the provenance is the only clue.
  static String? canonical(String text) {
    final probe = text.trim();
    if (probe.length < 8) return null;

    for (final entry in _bank.entries) {
      if (probe == entry.key || probe.contains(entry.key)) return entry.value;
    }
    for (final entry in _bank.entries) {
      if (TextSimilarity.jaroWinkler(probe, entry.key) >= 0.90) {
        return entry.value;
      }
    }
    return null;
  }

  /// Every canonical target, for the test that keeps the bank honest.
  static Set<String> get targets => _bank.values.toSet();
}
