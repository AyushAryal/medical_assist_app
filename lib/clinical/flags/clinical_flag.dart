/// A derived, explainable warning about a patient or a record.
///
/// One type carries every warning the app raises — an unknown allergy status,
/// an elevated NEWS2, a possible duplicate, an unsigned note past its
/// threshold. That single shape is what lets a banner, a triage score and a
/// worklist all consume the same signal instead of each re-deriving it and
/// drifting apart.
///
/// A flag is a *conclusion with its evidence attached*: it never appears
/// without a [reason] a clinician can read and a [source] naming where it came
/// from. Nothing derived is shown in this app without a "why".
library;

/// How loudly a flag should read. Maps to the reserved clinical severity
/// palette in the UI layer — and only there. The kernel stays free of colour.
enum FlagSeverity { info, caution, critical }

extension FlagSeverityX on FlagSeverity {
  /// Critical is the only level that changes triage precedence, so it earns a
  /// predicate rather than call sites comparing enum values by hand.
  bool get isCritical => this == FlagSeverity.critical;
}

/// What *kind* of thing a flag is, so rules match on a typed value instead of
/// sniffing display text. A triage rule that keyed off the words in [title]
/// would silently misbehave the day a title is reworded; this cannot.
enum FlagKind {
  allergyUnknown,
  elevatedNews2,
  redFlag,
  possibleDuplicate,
  unsignedNote,
  overdueReview,
}

/// A single warning, derived by a [FlagRule] from a record.
class ClinicalFlag {
  const ClinicalFlag({
    required this.subjectId,
    required this.kind,
    required this.severity,
    required this.title,
    required this.reason,
    required this.source,
  });

  /// The patient (or other subject) the flag is about.
  final String subjectId;
  final FlagKind kind;
  final FlagSeverity severity;

  /// A short heading — "Elevated NEWS2", "Allergies not recorded".
  final String title;

  /// The human-readable derivation — "NEWS2 8 (high) from observations at
  /// 14:32". This is the "why" surfaced behind an InfoDot.
  final String reason;

  /// Where the conclusion came from — the row or field it was read off, so the
  /// flag is auditable rather than a floating assertion.
  final String source;

  bool get isCritical => severity.isCritical;

  @override
  String toString() => 'ClinicalFlag(${kind.name}, ${severity.name}, $title)';
}
