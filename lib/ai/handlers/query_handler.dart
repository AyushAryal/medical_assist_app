import '../cohort/assist_reply.dart';
import '../cohort/cohort_query.dart';
import '../cohort/query_router.dart';
import '../../data/dao/cohort_dao.dart';
import '../../data/repositories/clinical_repository.dart';
import '../intent.dart';
import '../presentation.dart';
import '../provenance.dart';

/// Runs a read against the register and shapes the answer.
///
/// The single implementation. Before this existed the bubble and the full page
/// each had their own copy of "fetch rows, count, look for mentions, choose
/// wording", and they drifted twice — once over whether a counting question
/// should also list records, once over what happens when nothing matched.
/// Anything that has to be right in two places is eventually right in one.
class QueryHandler {
  const QueryHandler(this._repository);

  final ClinicalRepository _repository;

  /// How many records accompany a count. Enough to act on, few enough that the
  /// number stays the answer.
  static const int inlineRows = 25;

  Future<Presentation> run(
    QueryIntent intent,
    Provenance provenance, {
    int rowLimit = inlineRows,
  }) async {
    final query = intent.query;

    // Nothing but words to search for. Counting patients here would report the
    // whole register, because a query with no filter matches everything.
    if (query.isTextOnly) {
      final mentions = await _repository.cohorts.mentionsAny(
        query.freeTextTerms,
        limit: rowLimit,
      );
      provenance.add(
        'execute',
        'Searched what people wrote',
        detail: 'No structured filter matched, so the words were looked for '
            'in free text across every prose field.',
      );
      return MentionsPresentation(
        mentions: mentions,
        terms: query.freeTextTerms,
        headline: mentions.isEmpty
            ? 'Nothing on the register mentions that.'
            : '${mentions.length} '
                '${mentions.length == 1 ? 'record mentions' : 'records mention'}'
                ' that.',
        explanation: query.explain(resultCount: mentions.length),
      );
    }

    // Rows are fetched even for a counting question. "Appointments today: 6"
    // with no way to see which six is a dead end.
    final rows = await _rows(query, rowLimit);
    final value = await _value(query);

    final mentions = query.freeTextTerms.isEmpty
        ? const <TextMention>[]
        : await _repository.cohorts.mentionsAny(
            query.freeTextTerms,
            excludePatientIds: <String>{for (final r in rows) r.patient.id},
            limit: 10,
          );

    provenance.add(
      'execute',
      'Searched ${query.entity.label.toLowerCase()}',
      detail: query.describe().skip(1).join(' · '),
    );

    final routed = RoutedQuery(
      query: query,
      matched: intent.matched,
      confidence: intent.confidence,
    );
    final reply = value == 0 && !query.isEmpty
        ? AssistReplies.emptyWithAdvice(routed)
        : AssistReplies.answer(
            routed: routed,
            value: value,
            mentions: mentions.length,
          );

    // The projected columns, one formatted cell per field per person. The
    // fields format their own values (kind-aware, one implementation) so the
    // renderer never gets a second chance to format the same number
    // differently.
    final projection = intent.projection;
    final cells = <List<String>>[
      for (final row in rows)
        <String>[
          for (final field in projection)
            field.display(row.patient.toMap()),
        ],
    ];
    if (projection.isNotEmpty) {
      provenance.add(
        'present',
        'Projected ${projection.length} '
            'column${projection.length == 1 ? '' : 's'}',
        detail: projection.map((f) => f.label).join(', '),
      );
    }

    return MetricPresentation(
      value: value,
      label: query.entity.noun,
      headline: reply.text,
      rows: rows,
      total: value,
      columns: <String>[for (final field in projection) field.label],
      cells: projection.isEmpty ? const <List<String>>[] : cells,
      preferTable: intent.preferTable,
      explanation: query.explain(resultCount: value),
    );
  }

  /// The secondary list, for records the structured filters could not know
  /// about. Returned separately so it is never folded into the count.
  Future<MentionsPresentation?> mentionsFor(
    CohortQuery query, {
    required Set<String> exclude,
  }) async {
    if (query.freeTextTerms.isEmpty || query.isTextOnly) return null;
    final mentions = await _repository.cohorts.mentionsAny(
      query.freeTextTerms,
      excludePatientIds: exclude,
      limit: 20,
    );
    if (mentions.isEmpty) return null;

    return MentionsPresentation(
      mentions: mentions,
      terms: query.freeTextTerms,
      headline: '${mentions.length} more '
          '${mentions.length == 1 ? 'record' : 'records'} mention it in prose',
    );
  }

  Future<List<CohortRow>> _rows(CohortQuery query, int limit) {
    return switch (query.entity) {
      QueryEntity.appointments =>
        _repository.cohorts.appointments(query, limit: limit),
      QueryEntity.vitals => _repository.cohorts.vitals(query, limit: limit),
      QueryEntity.notes => _repository.cohorts.notes(query, limit: limit),
      QueryEntity.files => _repository.cohorts.files(query, limit: limit),
      QueryEntity.patients =>
        _repository.cohorts.patients(query, limit: limit),
      QueryEntity.visits => _repository.cohorts.patients(query, limit: limit),
    };
  }

  Future<int> _value(CohortQuery query) {
    return switch (query.entity) {
      QueryEntity.appointments => _repository.cohorts.appointmentCount(query),
      QueryEntity.visits => _repository.cohorts.encounterCount(query),
      QueryEntity.vitals => _repository.cohorts.vitalsCount(query),
      QueryEntity.notes => _repository.cohorts.noteCount(query),
      QueryEntity.files => _repository.cohorts.fileCount(query),
      QueryEntity.patients => query.kind == CohortQueryKind.activity
          ? _repository.cohorts.encounterCount(query)
          : _repository.cohorts.count(query),
    };
  }
}
