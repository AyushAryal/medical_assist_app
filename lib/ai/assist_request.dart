/// Where a request came from.
///
/// Recorded because it changes how the result should be handled, not for
/// analytics: a dictated question carries transcription error that a typed one
/// does not, and anything a machine produced from it deserves a lower
/// confidence and a visible provenance trail.
enum RequestSource { typed, dictated, suggestion, programmatic }

/// One piece of a request.
///
/// Sealed, because the set of things a request can be made of is exactly the
/// kind of thing that grows: today every request is text, but a photographed
/// referral letter, a lab report PDF or a recorded question are all plausible
/// inputs to the same pipeline. When one arrives it is a new case here and a
/// new interpreter that declares it can read it — not a rewrite of the
/// request type and every call site that touches it.
///
/// A part carries *input*, never meaning. Interpretation happens downstream,
/// after preprocessing, where it can be redacted and traced.
sealed class RequestPart {
  const RequestPart();
}

/// Words, typed or transcribed.
class TextPart extends RequestPart {
  const TextPart(this.text);

  final String text;
}

/// One thing asked of the assistant.
///
/// Carries *who* is asking as well as *what*, because the answer legitimately
/// differs: a request that would create or change a record has to be checked
/// against what this clinician is allowed to do, and every stage of the
/// pipeline has to be able to say which clinic's data it was working in.
class AssistRequest {
  /// The common case: a question in words. [parts] is for anything richer.
  AssistRequest({
    String? text,
    List<RequestPart> parts = const <RequestPart>[],
    required this.source,
    this.actor,
    this.clinicId,
    this.asOf,
  }) : parts = List.unmodifiable(<RequestPart>[
          if (text != null) TextPart(text),
          ...parts,
        ]);

  /// Everything that was handed over, verbatim and in order. Never normalised
  /// in place — preprocessing produces a *new* value, so the original is
  /// always available to show back to the person who asked.
  final List<RequestPart> parts;

  final RequestSource source;

  /// The signing clinician, for authorisation and for the audit trail.
  final String? actor;

  /// The clinic in context. Some questions are scoped to it and some are not,
  /// and the difference has to be stated in the answer rather than assumed.
  final String? clinicId;

  /// Overridable clock, so "this month" is testable.
  final DateTime? asOf;

  DateTime get now => asOf ?? DateTime.now();

  /// The textual content, joined. What every text interpreter reads.
  String get text => parts
      .whereType<TextPart>()
      .map((part) => part.text)
      .join(' ')
      .trim();

  bool get hasText => parts.whereType<TextPart>().any(
        (part) => part.text.trim().isNotEmpty,
      );
}
