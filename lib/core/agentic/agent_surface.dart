/// The contract that makes a screen's fields operable by an agent.
///
/// An "agent" here is anything that can fill a form on the clinician's behalf
/// — the guided voice flow today, a larger cloud model or a local one later.
/// Rather than let a model poke at arbitrary widgets (unauditable, and against
/// this app's rule that a model chooses among options a human defined), a
/// screen publishes an [AgentSurface]: an ordered, named, typed set of the
/// fields it is willing to have filled. A driver reads that surface, decides a
/// value, and *proposes* it — the propose callbacks set an unconfirmed value
/// the clinician still reviews and saves. Nothing here writes to a record.
///
/// Pure Dart, no Flutter, so both the surface and the drivers over it are
/// unit-testable without a widget tree.
library;

/// What kind of value a field accepts, so a driver knows how to fill it.
enum AgentFieldKind { integer, decimal, pair, text }

/// One field a widget exposes for an agent to fill.
///
/// Exactly one propose callback is set, matching [kind]: [proposeNumber] for
/// integer/decimal, [proposePair] for a paired reading like blood pressure,
/// [proposeText] for free text. A field with no matching callback is display
/// only and an agent must skip it.
class AgentField {
  const AgentField({
    required this.id,
    required this.label,
    required this.kind,
    this.unit,
    this.proposeNumber,
    this.proposePair,
    this.proposeText,
  });

  /// Stable identifier, e.g. `systolic`. What a model names when it chooses.
  final String id;

  /// Human- and agent-readable name, e.g. `Systolic blood pressure`.
  final String label;

  /// Unit shown on read-back, e.g. `mmHg`. Null when the field has none.
  final String? unit;

  final AgentFieldKind kind;

  final void Function(num value)? proposeNumber;
  final void Function(int first, int second)? proposePair;
  final void Function(String value)? proposeText;

  /// True when this field can actually be filled by an agent (a matching
  /// propose callback is present for its kind).
  bool get isFillable => switch (kind) {
        AgentFieldKind.integer || AgentFieldKind.decimal => proposeNumber != null,
        AgentFieldKind.pair => proposePair != null,
        AgentFieldKind.text => proposeText != null,
      };
}

/// The ordered set of agent-operable fields a screen currently exposes.
class AgentSurface {
  const AgentSurface(this.fields);

  final List<AgentField> fields;

  /// Only the fields a driver can actually fill, in order.
  List<AgentField> get fillable =>
      fields.where((f) => f.isFillable).toList(growable: false);

  AgentField? byId(String id) {
    for (final field in fields) {
      if (field.id == id) return field;
    }
    return null;
  }
}
