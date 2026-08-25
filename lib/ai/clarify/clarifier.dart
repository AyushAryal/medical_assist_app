import '../analytics/analysis.dart';
import '../analytics/analysis_examples.dart';
import '../cohort/query_vocabulary.dart';
import '../schema/field_registry.dart';
import '../../core/utils/text_similarity.dart';

/// A question asked back, with tappable ways to answer it.
typedef Clarification = ({String prompt, List<({String label, String question})> options});

/// Builds the question to ask when a question was not understood.
///
/// The alternative — "not understood, here is a syntax guide" — makes the
/// *user* do the repair work, and they do it by trial and error. A colleague
/// who half-heard you asks one targeted question instead: "measured how — the
/// average, or who's highest?". This produces that question, and every option
/// on it is a complete question the app provably answers, so answering is one
/// tap and cannot fail.
///
/// It is deliberately conservative. An option is only offered when something
/// in what was typed actually points at it; with no signal at all the honest
/// output is null and the caller falls back to the plain "not understood",
/// because a clarifier that always has suggestions is a search engine's
/// "did you mean", not a colleague.
abstract final class Clarifier {
  /// Words too common to point at anything.
  static const Set<String> _stop = <String>{
    'the', 'a', 'an', 'of', 'in', 'for', 'on', 'at', 'to', 'and', 'or',
    'is', 'are', 'was', 'were', 'do', 'does', 'my', 'our', 'me', 'we',
    'all', 'any', 'some', 'that', 'this', 'those', 'these', 'with', 'their',
    'what', 'whats', 'which', 'who', 'how', 'about', 'many',
  };

  static Clarification? attempt(String text) {
    final tokens = _tokens(text);
    if (tokens.isEmpty) return null;

    if (measureSlot(text) case final slot?) return slot;

    // Otherwise: the advertised questions nearest to what was typed. The bank
    // is the same starters and generated examples the guide shows, so an
    // option here is never a promise the app cannot keep.
    final near = _nearestQuestions(tokens);
    if (near.isEmpty) return null;

    return (
      prompt: 'I did not quite get that — is one of these close?',
      options: near,
    );
  }

  /// The commonest near-miss, precisely answerable: an aggregate word with a
  /// measure it could not pin down — "average pressure", "mean sugar levels".
  ///
  /// Exposed separately because the pipeline also uses it as a *veto*: a
  /// question carrying a measurement word that fell all the way through to
  /// the free-text prose search was almost certainly a misparsed calculation,
  /// and searching the notes for "average pressure levels" answers a question
  /// nobody asked. Asking beats both guesses.
  static Clarification? measureSlot(String text) {
    final aggregate = _aggregateIn(text.toLowerCase());
    if (aggregate == null) return null;
    final measures = _measureCandidates(_tokens(text));
    if (measures.isEmpty) return null;

    return (
      prompt: 'I can work out ${aggregate.article} of a few things like '
          'that — which did you mean?',
      options: <({String label, String question})>[
        for (final measure in measures.take(3))
          (
            label: measure.label,
            question:
                '${aggregate.triggers.first} ${measure.synonyms.isEmpty ? measure.label.toLowerCase() : measure.synonyms.first}',
          ),
      ],
    );
  }

  static Aggregate? _aggregateIn(String text) {
    for (final aggregate in Aggregate.values) {
      for (final trigger in aggregate.triggers) {
        if (RegExp('\\b${RegExp.escape(trigger)}\\b').hasMatch(text)) {
          return aggregate;
        }
      }
    }
    return null;
  }

  /// Numeric fields any stray token points at, best first.
  static List<DataField> _measureCandidates(List<String> tokens) {
    final scored = <({DataField field, double score})>[];
    for (final table in FieldRegistry.tables) {
      for (final field in table.ofKind(FieldKind.numeric)) {
        var best = 0.0;
        for (final token in tokens) {
          for (final word in <String>[field.label, ...field.synonyms]) {
            for (final part in word.toLowerCase().split(' ')) {
              final score = TextSimilarity.jaroWinkler(token, part);
              if (score > best) best = score;
            }
          }
        }
        if (best >= 0.84) scored.add((field: field, score: best));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final seen = <String>{};
    return <DataField>[
      for (final entry in scored)
        if (seen.add(entry.field.name)) entry.field,
    ];
  }

  static List<({String label, String question})> _nearestQuestions(
    List<String> tokens,
  ) {
    final bank = <String>[
      for (final group in QueryVocabulary.starters) ...group.starters,
      for (final example in AnalysisExamples.all) example.question,
    ];

    final scored = <({String question, double score})>[];
    for (final question in bank) {
      final bankTokens = _tokens(question);
      var matched = 0;
      for (final token in tokens) {
        final hit = bankTokens.any(
          (bankToken) => TextSimilarity.jaroWinkler(token, bankToken) >= 0.86,
        );
        if (hit) matched++;
      }
      if (matched == 0) continue;
      scored.add((question: question, score: matched / tokens.length));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    return <({String label, String question})>[
      for (final entry in scored.take(3))
        if (entry.score >= 0.5)
          (label: entry.question, question: entry.question),
    ];
  }

  static List<String> _tokens(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((token) => token.length >= 3 && !_stop.contains(token))
      .toList();
}
