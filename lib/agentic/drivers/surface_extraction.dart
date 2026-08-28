import '../../core/agentic/agent_surface.dart';
import 'spoken_value.dart';

/// What a structured extraction did to a surface.
class ExtractionResult {
  const ExtractionResult({
    required this.filled,
    required this.rejected,
    required this.unknown,
    this.displays = const <String, String>{},
  });

  /// Field ids that were proposed a valid value.
  final List<String> filled;

  /// Field id → the value as shown, e.g. `120/80`, for the preview.
  final Map<String, String> displays;

  /// Field ids whose extracted value failed validation (wrong kind, or outside
  /// the field's plausible bounds) and was refused.
  final List<String> rejected;

  /// Keys the model produced that match no field — dropped.
  final List<String> unknown;

  int get filledCount => filled.length;
}

/// Applies a model's structured extraction (e.g. `{"bp":"120/80","pulse":110}`)
/// to an [AgentSurface], proposing only values that survive validation.
///
/// This is the guard that makes a model a safe driver. A model may hallucinate
/// a field that does not exist, or a value that is nonsense — so nothing it
/// returns is trusted: unknown keys are dropped, values are coerced to the
/// field's kind, and anything outside the field's plausible bounds is refused
/// rather than proposed. It reuses the same [SpokenValueParser] as the voice
/// driver to read "120/80" or "one twenty over eighty" out of string values,
/// so the two drivers accept the same value shapes.
class SurfaceExtraction {
  const SurfaceExtraction({this.parser = const SpokenValueParser()});

  final SpokenValueParser parser;

  ExtractionResult apply(Map<String, Object?> data, AgentSurface surface) {
    final filled = <String>[];
    final rejected = <String>[];
    final unknown = <String>[];
    final displays = <String, String>{};

    for (final entry in data.entries) {
      final field = _resolve(entry.key, surface);
      if (field == null) {
        unknown.add(entry.key);
        continue;
      }
      final value = entry.value;
      if (value == null) continue; // model left it blank — not an error
      final display = _fill(field, value);
      if (display != null) {
        filled.add(field.id);
        displays[field.id] = display;
      } else {
        rejected.add(field.id);
      }
    }

    return ExtractionResult(
      filled: filled,
      rejected: rejected,
      unknown: unknown,
      displays: displays,
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
    // Looser: the key contains a field name ("systolic_bp" -> bp).
    for (final field in surface.fillable) {
      if (field.matchAlias(k) != null) return field;
    }
    return null;
  }

  /// Proposes [value] into [field] and returns the value as shown, or null if
  /// it fails validation and is refused.
  String? _fill(AgentField field, Object value) {
    String withUnit(String v) =>
        field.unit == null ? v : '$v ${field.unit}';
    switch (field.kind) {
      case AgentFieldKind.pair:
        final pair = _pair(value);
        if (pair == null) return null;
        if (!field.accepts(pair.$1) || !field.accepts(pair.$2)) return null;
        field.proposePair?.call(pair.$1, pair.$2);
        return withUnit('${pair.$1}/${pair.$2}');
      case AgentFieldKind.integer:
      case AgentFieldKind.decimal:
        final number = _num(value);
        if (number == null || !field.accepts(number)) return null;
        field.proposeNumber?.call(number);
        return withUnit(
          number == number.roundToDouble() ? '${number.toInt()}' : '$number',
        );
      case AgentFieldKind.text:
        if (field.proposeText == null) return null;
        field.proposeText!.call('$value');
        return '$value';
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
      if (utterance is PairUtterance) {
        return (utterance.first, utterance.second);
      }
    }
    return null;
  }
}
