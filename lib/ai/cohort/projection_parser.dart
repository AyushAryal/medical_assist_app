import '../schema/field_registry.dart';

/// What a projection parse produced: the columns asked for, and the question
/// with the asking removed.
typedef ProjectionParse = ({List<DataField> fields, String rest});

/// Reads the "and their contact numbers" off the end of a cohort question.
///
/// A projection changes what the table *shows*, never who is on it — so it is
/// peeled off before the cohort router runs, and the router sees the same
/// question it would have seen without it. "Patients on warfarin and their
/// phone numbers" filters exactly like "patients on warfarin".
///
/// Only patient attributes can be projected, because cohort rows are
/// patients. That restriction is also the safety valve: in "patients with
/// diabetes", the tail "diabetes" resolves to no patient field, the parse
/// declines, and the phrase stays what it is — a filter for the router.
abstract final class ProjectionParser {
  /// The joining words that introduce columns rather than filters.
  static final RegExp _tail = RegExp(
    r'\s+(?:and|plus|showing|including|along with)\s+(?:their\s+|the\s+)?(.+)$',
  );

  /// "Phone numbers of all patients" — the projection leads, the cohort
  /// follows.
  static final RegExp _leading = RegExp(
    r'^(.+?)\s+(?:of|for)\s+((?:all\s+|the\s+)?'
    r'(?:patients?|everyone|everybody|every patient|register))$',
  );

  static ProjectionParse parse(String text) {
    const none = <DataField>[];

    if (_leading.firstMatch(text) case final match?) {
      final fields = _resolveList(match.group(1)!);
      if (fields != null) return (fields: fields, rest: match.group(2)!);
    }

    if (_tail.firstMatch(text) case final match?) {
      final fields = _resolveList(match.group(1)!);
      if (fields != null) {
        return (fields: fields, rest: text.substring(0, match.start).trim());
      }
    }

    return (fields: none, rest: text);
  }

  /// "contact numbers, ages and email" → phone, age, email — or null if any
  /// part fails to resolve, because a half-understood projection silently
  /// shows fewer columns than were asked for.
  ///
  /// Parts are split on the joining words, but the preprocessor has already
  /// eaten the commas, so "age, phone number and email" arrives as one run of
  /// words. Each part therefore also gets a greedy longest-prefix pass: the
  /// longest leading word-run that names a field is taken, and the remainder
  /// must resolve the same way or the whole parse declines.
  static List<DataField>? _resolveList(String phrase) {
    final parts = phrase
        .split(RegExp(r'\s*(?:,|\band\b|\bplus\b)\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
    if (parts.isEmpty) return null;

    final fields = <DataField>[];
    for (final part in parts) {
      final resolved = _resolvePart(part);
      if (resolved == null) return null;
      for (final field in resolved) {
        if (!fields.contains(field)) fields.add(field);
      }
    }
    return fields;
  }

  static List<DataField>? _resolvePart(String part) {
    if (_field(part) case final field?) return <DataField>[field];

    final words = part.split(' ');
    // Longest prefix first, so "phone number" wins over "phone" + "number".
    for (var keep = words.length - 1; keep >= 1; keep--) {
      final head = _field(words.take(keep).join(' '));
      if (head == null) continue;
      final rest = _resolvePart(words.skip(keep).join(' '));
      if (rest != null) return <DataField>[head, ...rest];
    }
    return null;
  }

  static DataField? _field(String phrase) {
    final match =
        FieldRegistry.resolveField(phrase, within: FieldRegistry.patients);
    if (match == null ||
        match.table.name != FieldRegistry.patients.name ||
        match.field.kind == FieldKind.text) {
      return null;
    }
    return match.field;
  }
}
