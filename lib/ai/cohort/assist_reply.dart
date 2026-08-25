import 'cohort_query.dart';
import 'query_router.dart';
import 'query_vocabulary.dart';

/// What the assistant says back, and what it offers next.
///
/// Written as data rather than assembled in the widget so the wording can be
/// tested. The tone rule this encodes: **it is a colleague, not a validator.**
/// "Not understood" is a machine telling a clinician they typed wrong. "I'm not
/// sure which patients you mean — did you want any of these?" is a colleague
/// asking. The information is identical and only one of them gets used twice.
class AssistReply {
  const AssistReply({
    required this.text,
    this.suggestions = const <String>[],
    this.query,
    this.routed,
  });

  /// The sentence shown in the assistant's bubble.
  final String text;

  /// Better phrasings to offer, as tappable chips. Never a bare list of
  /// examples when something specific can be inferred from what was asked.
  final List<String> suggestions;

  final CohortQuery? query;
  final RoutedQuery? routed;

  bool get hasQuery => query != null;
}

abstract final class AssistReplies {
  /// The opening line. Says what it can do without listing rules at someone
  /// who has not asked a question yet.
  static AssistReply greeting() => AssistReply(
        text: 'Ask me about the register — patients, appointments, visits, '
            'observations, notes or files.',
        suggestions: QueryRouter.examples.take(3).toList(),
      );

  /// Nothing matched at all.
  ///
  /// Deliberately not phrased as a failure on the user's part, and never
  /// empty-handed: a dead end with no way forward is what makes people stop
  /// using a search.
  static AssistReply notUnderstood(String question) {
    final suggestions = QueryVocabulary.suggestionsFor(question);
    return AssistReply(
      text: "I'm not sure what to search for there. I can look through "
          'patients, appointments, visits, observations, notes and files — '
          'here are some questions I do understand:',
      suggestions: suggestions,
    );
  }

  /// Something matched, but thinly. Offers the sharper version of the same
  /// question rather than making the reader guess what would have worked.
  static AssistReply partial(RoutedQuery routed, String question) {
    return AssistReply(
      text: 'I searched for ${_phrase(routed.matched)}, but I did not follow '
          'all of that. Have a look at the filters — or try one of these:',
      suggestions: _sharperVersions(routed, question),
      query: routed.query,
      routed: routed,
    );
  }

  /// A question that matched no filter, answered by searching the prose.
  ///
  /// Kept separate from [answer] because the claim being made is a much
  /// smaller one, and saying so is the whole point. "I found 13 patients" for
  /// the word "hello" is not a near miss — it is an unfiltered query reported
  /// as a result, and it is exactly the failure this design exists to prevent.
  static AssistReply textOnly({
    required RoutedQuery routed,
    required int matches,
  }) {
    final terms = routed.query.anyTextOf.map((t) => '"$t"').join(' or ');

    return AssistReply(
      text: matches == 0
          ? 'I could not match that to anything I search by, and nothing on '
              'the register mentions $terms either.'
          : 'I could not match that to a filter, so I looked for $terms in '
              'what people have written. $matches '
              '${matches == 1 ? 'record mentions' : 'records mention'} it.',
      suggestions: matches == 0
          ? QueryVocabulary.suggestionsFor(routed.matched.join(' '))
          : const <String>[],
      query: routed.query,
      routed: routed,
    );
  }

  /// A confident answer.
  static AssistReply answer({
    required RoutedQuery routed,
    required int value,
    required int mentions,
  }) {
    final query = routed.query;
    final noun = query.entity.noun;
    final plural = value == 1 ? noun : '${noun}s';

    final opening = switch (query.kind) {
      CohortQueryKind.activity =>
        value == 0 ? 'None recorded.' : 'I found $value $plural.',
      CohortQueryKind.overdue => value == 0
          ? 'Nobody is overdue by that definition — which is good news.'
          : '$value $plural ${value == 1 ? 'is' : 'are'} overdue.',
      _ => value == 0
          ? 'Nobody on the register matches that.'
          : 'I found $value $plural.',
    };

    final tail = mentions > 0
        ? ' $mentions more ${mentions == 1 ? 'patient has' : 'patients have'} '
            'it mentioned in their notes without it being on a list — those '
            'are below, worth a look.'
        : '';

    return AssistReply(
      text: '$opening$tail',
      query: query,
      routed: routed,
    );
  }

  /// A result of zero that is worth explaining rather than just reporting.
  static AssistReply emptyWithAdvice(RoutedQuery routed) {
    final query = routed.query;
    final suggestions = <String>[];

    if (query.medication != null) {
      suggestions.add('everyone on ${query.medication!.toLowerCase()}');
    }
    if (query.periodFrom != null) {
      suggestions.add('${query.entity.triggerWords.first} this year');
    }
    if (query.ageBand != null) {
      suggestions.add(
        '${query.entity.triggerWords.first} '
        '${query.problem == null ? 'this month' : 'with '
            '${query.problem!.toLowerCase()}'}',
      );
    }

    return AssistReply(
      text: 'Nothing matched all of that. Widening one of the filters usually '
          'helps — the narrowest one is often the date.',
      suggestions: suggestions.isEmpty
          ? QueryRouter.examples.take(2).toList()
          : suggestions.take(3).toList(),
      query: query,
      routed: routed,
    );
  }

  /// Turns the matched-filter list into something readable in a sentence.
  static String _phrase(List<String> matched) {
    if (matched.isEmpty) return 'everything';
    if (matched.length == 1) return matched.first;
    return '${matched.take(matched.length - 1).join(', ')} '
        'and ${matched.last}';
  }

  /// Concrete better phrasings, built from what *was* understood.
  ///
  /// Offering the generic example list here would be the lazy answer, and it
  /// is the one that teaches nothing: the reader has to work out for
  /// themselves which part of their question failed.
  static List<String> _sharperVersions(RoutedQuery routed, String question) {
    final query = routed.query;
    final out = <String>[];
    final table = query.entity.triggerWords.first;

    if (query.medication != null) {
      out.add('everyone on ${query.medication!.toLowerCase()}');
    }
    if (query.problem != null) {
      out.add('${query.problem!.toLowerCase()} patients not seen in 6 months');
    }
    if (query.nameStartsWith != null) {
      out.add('patients with name starting with ${query.nameStartsWith}');
    }
    if (query.periodFrom == null) {
      out.add('$table this month');
    }
    if (query.entity == QueryEntity.patients && out.length < 3) {
      out.add('all patients');
    }

    return out.isEmpty
        ? QueryVocabulary.suggestionsFor(question)
        : out.take(3).toList();
  }
}
