import 'assist_request.dart';
import 'provenance.dart';

/// What preprocessing produced.
class Preprocessed {
  const Preprocessed({
    required this.original,
    required this.normalised,
    required this.redactions,
  });

  final String original;

  /// What interpreters see: lower-cased, depunctuated, stripped of framing.
  final String normalised;

  /// Values removed before anything downstream — and before any model — sees
  /// the text.
  final List<String> redactions;

  bool get isEmpty => normalised.trim().isEmpty;
}

/// The stage every request passes through before anything tries to understand
/// it.
///
/// Two jobs, and the second is the one that matters:
///
/// 1. **Normalise**, so "Could you please show me all the patients?" and
///    "patients" are the same request. Interpreters should be matching on
///    meaning, not absorbing every way a sentence can be wrapped.
///
/// 2. **Redact**, so that if a model is ever added it cannot receive a patient
///    identifier. Today every interpreter is coded logic running on-device and
///    nothing leaves the process, so this looks like ceremony. It is the
///    opposite: the moment a model is introduced is the moment it is easiest
///    to forget, and a redaction stage that was always there cannot be
///    forgotten. The normalised text keeps placeholders so an interpreter can
///    still tell that *an* identifier was mentioned.
abstract final class Preprocessor {
  static Preprocessed run(AssistRequest request, Provenance provenance) {
    final original = request.text;
    var text = original.toLowerCase().trim();
    final redactions = <String>[];

    // Identifiers first, before anything that might rewrite them.
    text = text.replaceAllMapped(
      RegExp(r'\b\d{6,}\b'),
      (match) {
        redactions.add(match.group(0)!);
        return '«id»';
      },
    );

    // Politeness and framing, which appear at the start and mean nothing.
    text = text.replaceAll(
      RegExp(
        r'\b(?:can you|could you|would you|please|kindly|i want to|'
        r'i need to|i would like to|show me|give me|tell me|find me|get me|'
        r'let me see|display|fetch|search for|look up|look for|pull up|'
        // "What about" and "how about" are deliberately absent: they mark a
        // refinement of the previous question and the conversation layer
        // needs to see them.
        r'list out|list me|hey|hi)\b',
      ),
      ' ',
    );

    text = text.replaceAll(
      RegExp(r'\b(?:just|simply|actually|really|basically|kind of|sort of|'
          r'the whole|entire|complete|full)\b'),
      ' ',
    );

    // Apostrophes and hyphens stay: they are inside names and inside "haven't".
    text = text.replaceAll(RegExp(r'[?!.,;:]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    provenance.add(
      'preprocess',
      redactions.isEmpty
          ? 'Tidied the wording'
          : 'Tidied the wording and set aside '
              '${redactions.length} identifier'
              '${redactions.length == 1 ? '' : 's'}',
      detail: text == original.toLowerCase().trim()
          ? null
          : 'Read as: "$text"',
    );

    return Preprocessed(
      original: original,
      normalised: text,
      redactions: redactions,
    );
  }

  /// Puts redacted identifiers back, for a stage that legitimately needs them —
  /// an MRN lookup, for instance, which is coded logic and never a model.
  static String restore(Preprocessed input) {
    var text = input.normalised;
    for (final value in input.redactions) {
      text = text.replaceFirst('«id»', value);
    }
    return text;
  }
}
