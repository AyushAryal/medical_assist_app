import '../flags/clinical_flag.dart';
import '../news2.dart';
import 'worklist.dart';

/// The triage rule: "who do I see first" for the patients currently waiting.
///
/// Pure and deterministic. It ranks a snapshot of waiting patients and nothing
/// else — no I/O, no clock of its own (the snapshot's [TriageReadModel.asOf] is
/// the clock), no model. The whole ordering is pinned by tests, because on a
/// triage board an ambiguous order is a safety defect.
///
/// The one judgement worth stating plainly: a patient whose NEWS2 **cannot be
/// scored** (no or incomplete observations, or out of NEWS2's validated scope)
/// is *unknown* risk, not *low* risk. Sorting them below a measured-and-
/// reassuring "low" patient would imply the opposite of the truth. So they sit
/// in their own tier — below a *confirmed* medium/high emergency, but above the
/// measured low bands — and are grouped apart as "needs observations".

/// A minimal projection of one waiting patient — everything the rule needs and
/// nothing it does not. The data layer maps DB rows into this; the kernel never
/// depends on the full record models, which keeps `clinical/` liftable and lets
/// the rule be tested with hand-built fixtures.
class TriageSubject {
  const TriageSubject({
    required this.patientId,
    required this.mrn,
    required this.displayName,
    required this.arrivedAt,
    required this.risk,
    required this.unavailableReason,
    this.news2Total,
    this.vitalsRecordedAt,
    this.vitalsRecordId,
    this.flags = const <ClinicalFlag>[],
  }) : assert(
          (risk == null) != (unavailableReason == null),
          'A subject is either scored (risk set) or not (reason set) — never '
          'both, never neither.',
        );

  final String patientId;
  final String mrn;
  final String displayName;
  final DateTime arrivedAt;

  /// The NEWS2 band, or null when the patient could not be scored.
  final News2Risk? risk;

  /// Why the patient could not be scored, or null when they were.
  final News2Unavailable? unavailableReason;

  final int? news2Total;
  final DateTime? vitalsRecordedAt;
  final String? vitalsRecordId;
  final List<ClinicalFlag> flags;

  bool get isScored => risk != null;
  bool get hasCriticalFlag => flags.any((f) => f.isCritical);

  /// Builds a subject straight from observations, running the one shared
  /// [News2Calculator] so the score on the board is the same score everywhere
  /// else. Pass [observations] as null when nothing was recorded at all.
  factory TriageSubject.fromObservations({
    required String patientId,
    required String mrn,
    required String displayName,
    required DateTime arrivedAt,
    required int? ageYears,
    required bool isPregnant,
    required News2Input? observations,
    DateTime? vitalsRecordedAt,
    String? vitalsRecordId,
    List<ClinicalFlag> flags = const <ClinicalFlag>[],
  }) {
    final input = observations ?? const News2Input();
    final reason = News2Calculator.unavailableReason(
      ageYears: ageYears,
      isPregnant: isPregnant,
      input: input,
    );
    final result = reason == null
        ? News2Calculator.score(
            ageYears: ageYears,
            isPregnant: isPregnant,
            input: input,
          )
        : null;
    return TriageSubject(
      patientId: patientId,
      mrn: mrn,
      displayName: displayName,
      arrivedAt: arrivedAt,
      risk: result?.risk,
      unavailableReason: result == null ? reason : null,
      news2Total: result?.total,
      vitalsRecordedAt: vitalsRecordedAt,
      vitalsRecordId: vitalsRecordId,
      flags: flags,
    );
  }
}

/// The snapshot the rule runs over: every currently-waiting patient, assembled
/// once and stamped with the instant it was taken.
class TriageReadModel {
  const TriageReadModel({required this.asOf, required this.subjects});

  final DateTime asOf;
  final List<TriageSubject> subjects;
}

/// Section keys the triage rule assigns to [WorklistEntry.group].
abstract final class TriageGroup {
  /// Scored patients, and any patient carrying a critical flag.
  static const String attention = 'attention';

  /// Not scored and no critical flag — risk unknown until observations exist.
  static const String needsObs = 'needsObs';
}

abstract final class TriageWorklist {
  static const String worklistId = 'triage';

  /// Ranks the snapshot. Every waiting patient is listed exactly once — a
  /// triage board that hides anyone is a defect — so [Worklist.excluded] is
  /// empty by construction and `considered == entries.length`.
  static Worklist build(TriageReadModel model) {
    final ordered = <TriageSubject>[...model.subjects]..sort(
        (a, b) => _compare(a, b),
      );

    final entries = <WorklistEntry>[];
    for (var i = 0; i < ordered.length; i++) {
      final s = ordered[i];
      final wait = _waitOf(s, model.asOf);
      entries.add(
        WorklistEntry(
          patientId: s.patientId,
          rank: i + 1,
          score: s.news2Total,
          group: s.isScored ? TriageGroup.attention
              : s.hasCriticalFlag ? TriageGroup.attention
              : TriageGroup.needsObs,
          reasons: _reasons(s, wait),
          provenance: _provenance(s),
        ),
      );
    }

    return Worklist(
      id: worklistId,
      title: 'Triage',
      asOf: model.asOf,
      entries: entries,
      considered: model.subjects.length,
    );
  }

  /// Total order. Each key is compared in turn; the final MRN key guarantees
  /// two otherwise-identical subjects still have one fixed order, so the board
  /// never reshuffles between reads.
  static int _compare(TriageSubject a, TriageSubject b) {
    final byTier = _tier(a).compareTo(_tier(b));
    if (byTier != 0) return byTier;

    // Critical flag first, within a tier.
    final critical = (a.hasCriticalFlag ? 0 : 1)
        .compareTo(b.hasCriticalFlag ? 0 : 1);
    if (critical != 0) return critical;

    // Longest wait first — i.e. earliest arrival first.
    final byArrival = a.arrivedAt.compareTo(b.arrivedAt);
    if (byArrival != 0) return byArrival;

    return a.mrn.compareTo(b.mrn);
  }

  /// Lower is seen sooner. "Needs observations" (unknown risk) sits below a
  /// confirmed medium/high emergency but above the measured low bands — never
  /// treated as low risk.
  static int _tier(TriageSubject s) {
    switch (s.risk) {
      case News2Risk.high:
        return 0;
      case News2Risk.medium:
        return 1;
      case News2Risk.lowMedium:
        return 3;
      case News2Risk.low:
        return 4;
      case null:
        return 2; // not scored — risk unknown
    }
  }

  static Duration _waitOf(TriageSubject s, DateTime asOf) {
    final d = asOf.difference(s.arrivedAt);
    return d.isNegative ? Duration.zero : d;
  }

  static List<String> _reasons(TriageSubject s, Duration wait) {
    final reasons = <String>[
      if (s.isScored)
        'NEWS2 ${s.news2Total} (${s.risk!.label.toLowerCase()})'
      else
        'Risk unknown — ${_unavailableLabel(s.unavailableReason!)}',
      for (final f in s.flags.where((f) => f.isCritical)) 'Red flag: ${f.title}',
      _waitLabel(wait),
    ];
    return reasons;
  }

  static List<ProvenanceRef> _provenance(TriageSubject s) => <ProvenanceRef>[
        ProvenanceRef(label: 'Arrival', at: s.arrivedAt),
        if (s.vitalsRecordedAt != null)
          ProvenanceRef(
            label: 'Observations',
            entityId: s.vitalsRecordId,
            at: s.vitalsRecordedAt,
          ),
      ];

  static String _unavailableLabel(News2Unavailable reason) => switch (reason) {
        News2Unavailable.ageOutOfScope => 'outside NEWS2 age scope',
        News2Unavailable.pregnancy => 'not scored in pregnancy',
        News2Unavailable.incompleteObservations => 'observations incomplete',
      };

  static String _waitLabel(Duration wait) {
    final minutes = wait.inMinutes;
    if (minutes < 1) return 'just arrived';
    if (minutes < 60) return 'waiting $minutes min';
    final h = wait.inHours;
    final m = minutes - h * 60;
    return m == 0 ? 'waiting ${h}h' : 'waiting ${h}h ${m}m';
  }
}
