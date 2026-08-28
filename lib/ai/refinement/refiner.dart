import '../analytics/analysis.dart';
import '../analytics/analysis_parser.dart';
import '../analytics/period_parser.dart';
import '../cohort/cohort_query.dart';
import '../cohort/query_router.dart';
import '../intent.dart';
import '../interpreters/pattern_interpreter.dart';
import '../schema/field_registry.dart';

/// Reads a fragment as a change to the standing question.
///
/// This is the piece that turns a search box into a conversation. "Patients
/// on warfarin" followed by "only the women" is one question narrowed, not
/// two questions — and a system that answers the second as "all women on the
/// register" has forgotten what it was just asked, which is the failure that
/// makes an assistant feel like a form.
///
/// Everything here is coded logic over the same extractors the interpreters
/// already use: the cohort router reads the fragment's filters, the analysis
/// parser reads its modifiers, and the merge is field-by-field onto the
/// standing intent's own spec. The merged intent then flows through the same
/// authorisation, execution and provenance as any other — a refined question
/// is not a special path, it is a new intent with a remembered starting
/// point. The filters shown back on the answer are the *merged* set, so what
/// the conversation has accumulated is always on screen and always arguable.
abstract final class Refiner {
  /// The words that say "same question, changed" rather than "new question".
  ///
  /// "What about" and "how about" live here and not in the preprocessor's
  /// framing strip, precisely because they carry this meaning: "what about
  /// visits" after "appointments this month" is the same month, different
  /// table.
  static final RegExp _markers = RegExp(
    r'\b(?:only|just|them|those|these|of (?:those|them|whom)|what about|'
    r'how about|instead|same|narrow(?:ed)? (?:to|down)|also|as well|too|'
    r'make (?:it|that|them))\b',
  );

  /// Fragments that *are* modifiers — "per month", "as a pie", "top 20",
  /// "by district" — refine even without a marker word, but only when the
  /// question could not stand alone.
  static final RegExp _bareModifier = RegExp(
    r'^(?:per|by|as|top \d|above|over|below|under|between|this|last|in the last)\b',
  );

  /// Words that widen scope back out — "all", "everyone". A fragment that
  /// says these is asking for a fresh sweep, not a narrowing, even when a
  /// marker word sits next to them: "just show me all patients" after a
  /// warfarin question means the register, not warfarin again.
  static final RegExp _freshScope =
      RegExp(r'(?:all|every|everyone|everybody|whole register)');

  /// Decides whether the fragment refines [standing], and produces the merged
  /// intent if so. Null means "not a refinement — use the standalone reading".
  ///
  /// [raw] is the text as typed (lowercased), [fragment] the preprocessed
  /// version. Markers are read off the raw text on purpose: the preprocessor
  /// strips "just" as filler — rightly, for "just show me patients" — but in
  /// "just the women" it is the whole signal, and it must be seen before it
  /// is swept.
  static AssistIntent? refine({
    required AssistIntent? standing,
    required String raw,
    required String fragment,
    required AssistIntent standalone,
    DateTime? asOf,
  }) {
    if (standing == null) return null;
    final text = fragment.toLowerCase().trim();
    final asTyped = raw.toLowerCase().trim();
    if (text.isEmpty) return null;
    if (_freshScope.hasMatch(asTyped)) return null;

    // Precedence: a marker always means refinement, however well the fragment
    // parses alone — "only the women" parses perfectly as all-women and is
    // still not what was asked. Without a marker, a fragment only refines
    // when it could not stand as a question, so a fully-formed new question
    // always wins and a conversation can always change the subject.
    final marked = _markers.hasMatch(asTyped) || _markers.hasMatch(text);
    final helpless = standalone is UnknownIntent;
    final bare = _bareModifier.hasMatch(text);
    if (!marked && !helpless && !bare) return null;

    final merged = switch (standing) {
      QueryIntent() => _refineQuery(standing, text, asOf),
      ReportIntent() => _refineReport(standing, text, asOf),
      AnalysisIntent() => _refineAnalysis(standing, text, asOf),
      RankIntent() => _refineRank(standing, text, asOf),
      OverviewIntent() => _refineOverview(standing, text, asOf),
      // A patient summary is not a standing register query to refine — a
      // follow-up starts a fresh reading, not a filter tweak.
      PatientSummaryIntent() || MutationIntent() || UnknownIntent() => null,
    };

    // A marker with nothing mergeable ("make it nicer") falls through to the
    // standalone reading — which for a helpless fragment is the clarifier's
    // moment, not a silent guess.
    return merged;
  }

  // --- cohorts ------------------------------------------------------------

  static AssistIntent? _refineQuery(
    QueryIntent standing,
    String text,
    DateTime? asOf,
  ) {
    // A report cut on a cohort answer: "per week", "by age band" on
    // "diabetics" produces the filtered report, same as typing it longhand.
    final report = PatternInterpreter.reportKindIn(text);

    final routed = QueryRouter.route(text, asOf: asOf);
    final fragmentQuery = routed?.query;
    final query = fragmentQuery == null
        ? standing.query
        : _mergeCohort(standing.query, fragmentQuery, text);

    if (report != null) {
      return ReportIntent(
        kind: report,
        query: query,
        confidence: 0.8,
        matched: <String>[...standing.matched, ...?routed?.matched],
      );
    }
    if (fragmentQuery == null) return null;
    if (_sameCohort(query, standing.query)) return null;

    return QueryIntent(
      query: query,
      confidence: 0.8,
      matched: <String>[...standing.matched, ...routed!.matched],
      projection: standing.projection,
      preferTable: standing.preferTable,
    );
  }

  static AssistIntent? _refineReport(
    ReportIntent standing,
    String text,
    DateTime? asOf,
  ) {
    final kind = PatternInterpreter.reportKindIn(text);
    final routed = QueryRouter.route(text, asOf: asOf);
    final query = routed == null
        ? standing.query
        : _mergeCohort(standing.query, routed.query, text);

    if (kind == null && routed == null) return null;
    if (kind == null &&
        _sameCohort(query, standing.query)) {
      return null;
    }

    return ReportIntent(
      kind: kind ?? standing.kind,
      query: query,
      confidence: 0.8,
      matched: <String>[...standing.matched, ...?routed?.matched],
    );
  }

  /// Field-by-field overlay: the fragment wins wherever it says something,
  /// the standing query holds everywhere else.
  static CohortQuery _mergeCohort(
    CohortQuery standing,
    CohortQuery fragment,
    String text,
  ) {
    // The router defaults to `patients` when no table word appears, so an
    // entity swap only counts when the fragment actually named one — "what
    // about visits" swaps, "only the women" must not.
    final namedEntity = _namedEntity(text);

    return CohortQuery(
      kind: fragment.kind == CohortQueryKind.cohort
          ? standing.kind
          : fragment.kind,
      entity: namedEntity ?? standing.entity,
      nameStartsWith: fragment.nameStartsWith ?? standing.nameStartsWith,
      nameContains: fragment.nameContains ?? standing.nameContains,
      mrn: fragment.mrn ?? standing.mrn,
      appointmentStatus:
          fragment.appointmentStatus ?? standing.appointmentStatus,
      noteStatus: fragment.noteStatus ?? standing.noteStatus,
      news2AtLeast: fragment.news2AtLeast ?? standing.news2AtLeast,
      systolicAtLeast: fragment.systolicAtLeast ?? standing.systolicAtLeast,
      abnormalOnly: fragment.abnormalOnly || standing.abnormalOnly,
      fileKind: fragment.fileKind ?? standing.fileKind,
      mostRecent: fragment.mostRecent ?? standing.mostRecent,
      // Free text is not carried over: the words of the old question are not
      // filters on the new one.
      anyTextOf: fragment.anyTextOf,
      medication: fragment.medication ?? standing.medication,
      problem: fragment.problem ?? standing.problem,
      allergy: fragment.allergy ?? standing.allergy,
      ageBand: fragment.ageBand ?? standing.ageBand,
      sexAtBirth: fragment.sexAtBirth ?? standing.sexAtBirth,
      notSeenSince: fragment.notSeenSince ?? standing.notSeenSince,
      periodFrom: fragment.periodFrom ?? standing.periodFrom,
      periodTo: fragment.periodTo ?? standing.periodTo,
      clinicId: fragment.clinicId ?? standing.clinicId,
      visitType: fragment.visitType ?? standing.visitType,
      includeDeceased: fragment.includeDeceased || standing.includeDeceased,
    );
  }

  static bool _sameCohort(CohortQuery a, CohortQuery b) =>
      a.describe().join('|') == b.describe().join('|') && a.entity == b.entity;

  static QueryEntity? _namedEntity(String text) {
    for (final entity in QueryEntity.values) {
      for (final word in entity.triggerWords) {
        if (RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(text)) {
          return entity;
        }
      }
    }
    return null;
  }

  // --- analyses -----------------------------------------------------------

  static AssistIntent? _refineAnalysis(
    AnalysisIntent standing,
    String text,
    DateTime? asOf,
  ) {
    final pieces = AnalysisParser.fragments(text, asOf: asOf);
    if (!pieces.hasAny) return null;

    final spec = standing.spec;
    return AnalysisIntent(
      spec: AnalysisSpec(
        table: spec.table,
        aggregate: pieces.aggregate ?? spec.aggregate,
        measure: spec.measure,
        dimension: pieces.dimension?.field ??
            (pieces.bucket != null && spec.dimension == null
                ? spec.table.defaultTime
                : spec.dimension),
        dimensionTable: pieces.dimension?.table ??
            (pieces.bucket != null && spec.dimension == null
                ? spec.table
                : spec.dimensionTable),
        against: spec.against,
        againstTable: spec.againstTable,
        bucket: pieces.bucket ?? spec.bucket,
        style: pieces.style ?? spec.style,
        preferTable: spec.preferTable,
        periodFrom: pieces.periodFrom ?? spec.periodFrom,
        periodTo: pieces.periodTo ?? spec.periodTo,
        maxGroups: spec.maxGroups,
      ),
      confidence: 0.8,
      matched: standing.matched,
    );
  }

  // --- rankings -----------------------------------------------------------

  static AssistIntent? _refineRank(
    RankIntent standing,
    String text,
    DateTime? asOf,
  ) {
    var spec = standing.spec;
    var changed = false;

    if (RegExp(r'\b(?:top|first)\s+(\d{1,3})\b').firstMatch(text)
        case final match?) {
      spec = spec.copyWith(limit: int.parse(match.group(1)!).clamp(1, 100));
      changed = true;
    }

    if (RegExp(r'\b(above|over|at least|below|under|at most)\s+'
            r'(\d+(?:\.\d+)?)\b')
        .firstMatch(text) case final match?) {
      final upward = !RegExp(r'below|under|at most').hasMatch(match.group(1)!);
      spec = spec.copyWith(
        cutoff: double.parse(match.group(2)!),
        descending: upward,
      );
      changed = true;
    }

    final period = PeriodParser.take(text, asOf ?? DateTime.now());
    if (period.from != null) {
      spec = spec.copyWith(periodFrom: period.from, periodTo: period.to);
      changed = true;
    }

    // Demographics come from the cohort router — the same reading "women" and
    // "over 65" get everywhere else, so the two layers cannot disagree about
    // what a word means.
    if (QueryRouter.route(text, asOf: asOf) case final routed?) {
      if (routed.query.sexAtBirth case final sex?) {
        spec = spec.copyWith(sexAtBirth: sex);
        changed = true;
      }
      if (routed.query.ageBand case final band?) {
        spec = spec.copyWith(ageBand: band);
        changed = true;
      }
    }

    // "By BMI instead" — a new measure resets the cutoff, because a threshold
    // chosen for blood pressure is meaningless applied to weight.
    final byMeasure = RegExp(r'\bby\s+(.{2,40})$').firstMatch(text);
    if (byMeasure != null) {
      final match = FieldRegistry.resolveField(byMeasure.group(1)!.trim());
      if (match != null &&
          match.field.kind == FieldKind.numeric &&
          match.field.name != spec.measure.name) {
        spec = spec.copyWith(
          measure: match.field,
          table: match.table,
          clearCutoff: true,
        );
        changed = true;
      }
    }

    return changed
        ? RankIntent(spec: spec, confidence: 0.8, matched: standing.matched)
        : null;
  }

  static AssistIntent? _refineOverview(
    OverviewIntent standing,
    String text,
    DateTime? asOf,
  ) {
    final period = PeriodParser.take(text, asOf ?? DateTime.now());
    if (period.from == null) return null;
    return OverviewIntent(
      confidence: 0.85,
      periodFrom: period.from,
      periodTo: period.to,
    );
  }
}
