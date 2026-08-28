import '../../core/agentic/agent_surface.dart';
import 'spoken_value.dart';

/// A validated value ready to be proposed — held for preview until approved.
class StagedValue {
  const StagedValue({this.number, this.pair, required this.display});

  final num? number;
  final (int, int)? pair;

  /// The value as shown, e.g. `120/80 mmHg`.
  final String display;
}

/// What a structured extraction produced.
class ExtractionResult {
  const ExtractionResult({
    required this.values,
    required this.rejected,
    required this.unknown,
  });

  /// Field id → the validated value, for preview and later proposal.
  final Map<String, StagedValue> values;

  /// Field ids whose value failed validation (wrong kind, or outside the
  /// field's plausible bounds) and was refused.
  final List<String> rejected;

  /// Keys the model produced that match no field — dropped.
  final List<String> unknown;

  int get filledCount => values.length;
}

/// Validates a model's structured extraction (e.g. `{"bp":"120/80"}`) against
/// an [AgentSurface] — WITHOUT writing anything.
///
/// This is the guard that makes a model a safe driver. A model may hallucinate
/// a field that does not exist or a value that is nonsense, so nothing it
/// returns is trusted: unknown keys are dropped, values are coerced to the
/// field's kind, and anything outside the field's plausible bounds is refused.
/// It has no side effects — it returns validated [StagedValue]s that the caller
/// shows for review and only proposes into the form once the clinician approves.
class SurfaceExtraction {
  const SurfaceExtraction({this.parser = const SpokenValueParser()});

  final SpokenValueParser parser;

  ExtractionResult apply(Map<String, Object?> data, AgentSurface surface) {
    final values = <String, StagedValue>{};
    final rejected = <String>[];
    final unknown = <String>[];

    for (final entry in data.entries) {
      final field = _resolve(entry.key, surface);
      if (field == null) {
        unknown.add(entry.key);
        continue;
      }
      final value = entry.value;
      if (value == null) continue; // model left it blank — not an error
      final staged = _validate(field, value);
      if (staged != null) {
        values[field.id] = staged;
      } else {
        rejected.add(field.id);
      }
    }

    return ExtractionResult(
      values: values,
      rejected: rejected,
      unknown: unknown,
    );
  }

  AgentField? _resolve(String key, AgentSurface surface) {
    final k = key.toLowerCase().trim();
    for (final field in surface.fillable) {
      if (field.id.toLowerCase() == k ||
          field.label.toLowerCase() == k ||
          field.aliases.any((a) => a.toLowerCase() == k)) {
        return field;
      }
    }
    for (final field in surface.fillable) {
      if (field.matchAlias(k) != null) return field;
    }
    return null;
  }

  StagedValue? _validate(AgentField field, Object value) {
    String withUnit(String v) => field.unit == null ? v : '$v ${field.unit}';
    switch (field.kind) {
      case AgentFieldKind.pair:
        final pair = _pair(value);
        if (pair == null) return null;
        if (!field.accepts(pair.$1) || !field.accepts(pair.$2)) return null;
        return StagedValue(pair: pair, display: withUnit('${pair.$1}/${pair.$2}'));
      case AgentFieldKind.integer:
      case AgentFieldKind.decimal:
        final number = _num(value);
        if (number == null || !field.accepts(number)) return null;
        return StagedValue(
          number: number,
          display: withUnit(
            number == number.roundToDouble() ? '${number.toInt()}' : '$number',
          ),
        );
      case AgentFieldKind.text:
        if (field.proposeText == null) return null;
        return StagedValue(display: '$value');
    }
  }

  num? _num(Object value) {
    if (value is num) return value;
    if (value is String) {
      final utterance = parser.parse(value);
      if (utterance is NumberUtterance) return utterance.value;
      return num.tryParse(value.trim());
    }
    return null;
  }

  (int, int)? _pair(Object value) {
    if (value is List && value.length == 2) {
      final a = _num(value[0] as Object? ?? '');
      final b = _num(value[1] as Object? ?? '');
      if (a != null && b != null) return (a.round(), b.round());
    }
    if (value is Map) {
      final a = _num(value['systolic'] as Object? ?? value['first'] ?? '');
      final b = _num(value['diastolic'] as Object? ?? value['second'] ?? '');
      if (a != null && b != null) return (a.round(), b.round());
    }
    if (value is String) {
      final utterance = parser.parse(value);
      if (utterance is PairUtterance) return (utterance.first, utterance.second);
    }
    return null;
  }
}
