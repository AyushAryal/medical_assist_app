/// A ranked, self-explaining, *complete* list of patients.
///
/// Every physician worklist in the app — triage, recall, unfinished notes — is
/// one of these, produced by a pure rule over a read-model snapshot. Three
/// guarantees make a worklist safe to act on in a rush:
///
///  * **Total, deterministic order.** The same snapshot always yields the same
///    order, down to a final tie-break. No "roughly sorted".
///  * **Auditable completeness.** [considered] counts everyone the rule looked
///    at; [excluded] records everyone left off *and why*. A dropped patient is
///    therefore detectable, never invisible — see the constructor invariant.
///  * **Self-explaining entries.** Every entry carries its [reasons] and the
///    [provenance] behind them, for an InfoDot.
library;

/// A pointer back to the exact data a conclusion was read from, so a rank can
/// be audited rather than trusted.
class ProvenanceRef {
  const ProvenanceRef({required this.label, this.entityId, this.at});

  /// What the source is, in words — "Observations", "Arrival".
  final String label;

  /// The row it came from, when there is one.
  final String? entityId;

  /// When that data was recorded/observed, when it is time-stamped.
  final DateTime? at;

  @override
  String toString() =>
      'ProvenanceRef($label${entityId == null ? '' : ' #$entityId'})';
}

/// One patient's place on a worklist.
class WorklistEntry {
  const WorklistEntry({
    required this.patientId,
    required this.rank,
    required this.reasons,
    required this.provenance,
    this.score,
    this.group,
  });

  final String patientId;

  /// 1-based position after sorting. Assigned by the rule once the order is
  /// final, so the UI never re-sorts and never disagrees with the engine.
  final int rank;

  /// Why this patient sits here — "NEWS2 8 (high)", "waiting 42 min". Ordered
  /// most-significant first.
  final List<String> reasons;

  final List<ProvenanceRef> provenance;

  /// An optional numeric the rule sorted on, kept for display and debugging.
  final int? score;

  /// An optional rule-defined section key for grouped rendering (the triage
  /// rule uses it to hold "needs observations" apart from scored patients).
  /// The exact set of values is defined and tested by each rule.
  final String? group;
}

/// A patient the rule saw but left off the list, with the reason — the other
/// half of completeness.
class WorklistExclusion {
  const WorklistExclusion({required this.patientId, required this.reason});

  final String patientId;
  final String reason;
}

/// The result of running a worklist rule over a snapshot.
class Worklist {
  Worklist({
    required this.id,
    required this.title,
    required this.asOf,
    required this.entries,
    required this.considered,
    this.excluded = const <WorklistExclusion>[],
  }) : assert(
          considered == entries.length + excluded.length,
          'Completeness broken: considered ($considered) must equal '
          'included (${entries.length}) + excluded (${excluded.length}). '
          'A patient the rule looked at was neither listed nor accounted for.',
        );

  final String id;
  final String title;

  /// The snapshot instant the rule ran against. Ranks are relative to this,
  /// not to wall-clock at read time, so the list is reproducible.
  final DateTime asOf;

  /// Ranked, in display order.
  final List<WorklistEntry> entries;

  /// How many patients the rule considered — included plus excluded.
  final int considered;

  final List<WorklistExclusion> excluded;

  bool get isEmpty => entries.isEmpty;
}
