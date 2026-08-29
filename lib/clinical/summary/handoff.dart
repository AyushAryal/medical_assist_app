import '../flags/clinical_flag.dart';
import 'record_summary.dart';

/// A handoff, in SBAR — the standard shape for passing a patient between
/// clinicians at a shift change or a referral.
///
/// SBAR (Situation, Background, Assessment, Recommendation) is used rather than
/// a house style because a handoff is read under pressure by someone who was
/// not there, and a familiar structure is read faster and misread less. The
/// content is deterministic and inherits [RecordSummary]'s honesty: a gap is
/// stated as a gap, never smoothed over.

enum SbarPart { situation, background, assessment, recommendation }

extension SbarPartX on SbarPart {
  String get letter => switch (this) {
        SbarPart.situation => 'S',
        SbarPart.background => 'B',
        SbarPart.assessment => 'A',
        SbarPart.recommendation => 'R',
      };

  String get title => switch (this) {
        SbarPart.situation => 'Situation',
        SbarPart.background => 'Background',
        SbarPart.assessment => 'Assessment',
        SbarPart.recommendation => 'Recommendation',
      };
}

class HandoffLine {
  const HandoffLine({
    required this.text,
    this.state = SummaryState.recorded,
    this.severity,
  });

  final String text;
  final SummaryState state;
  final FlagSeverity? severity;

  bool get isRecorded => state == SummaryState.recorded;
}

class HandoffSection {
  const HandoffSection({required this.part, required this.lines});

  final SbarPart part;
  final List<HandoffLine> lines;
}

class Handoff {
  const Handoff({
    required this.patientId,
    required this.asOf,
    required this.identityLine,
    required this.sections,
  });

  final String patientId;
  final DateTime asOf;
  final String identityLine;
  final List<HandoffSection> sections;

  /// A copyable plain-text SBAR — for pasting into a message, a referral, or
  /// reading aloud. Deterministic, so the same record always renders the same
  /// handoff.
  String get plainText {
    final buffer = StringBuffer()
      ..writeln('SBAR handoff — $identityLine')
      ..writeln('As of ${_stamp(asOf)}')
      ..writeln();
    for (final section in sections) {
      buffer.writeln('${section.part.letter} — ${section.part.title}');
      for (final line in section.lines) {
        buffer.writeln('  • ${line.text}');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  static String _stamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// The inputs a handoff needs beyond the record pre-read: who the patient is,
/// why they are here, what is concerning, and what is outstanding.
class HandoffInput {
  const HandoffInput({
    required this.patientId,
    required this.asOf,
    required this.identityLine,
    required this.record,
    this.presentingComplaint,
    this.concerns = const <String>[],
    this.outstanding = const <String>[],
  });

  final String patientId;
  final DateTime asOf;
  final String identityLine;

  /// The prime-the-chart pre-read, reused for Background and the current score.
  final RecordSummary record;
  final String? presentingComplaint;

  /// Human-readable concerns — deteriorating trends, red flags.
  final List<String> concerns;

  /// Outstanding tasks — an unsigned note, a review due.
  final List<String> outstanding;
}

abstract final class HandoffBuilder {
  static Handoff build(HandoffInput input) {
    return Handoff(
      patientId: input.patientId,
      asOf: input.asOf,
      identityLine: input.identityLine,
      sections: <HandoffSection>[
        HandoffSection(part: SbarPart.situation, lines: _situation(input)),
        HandoffSection(part: SbarPart.background, lines: _background(input)),
        HandoffSection(part: SbarPart.assessment, lines: _assessment(input)),
        HandoffSection(
            part: SbarPart.recommendation, lines: _recommendation(input)),
      ],
    );
  }

  static List<HandoffLine> _situation(HandoffInput input) {
    final complaint = input.presentingComplaint?.trim();
    return <HandoffLine>[
      HandoffLine(text: input.identityLine),
      if (complaint != null && complaint.isNotEmpty)
        HandoffLine(text: 'Presenting: $complaint')
      else
        const HandoffLine(
          text: 'Reason for visit not recorded',
          state: SummaryState.notRecorded,
          severity: FlagSeverity.caution,
        ),
      _lineFrom(input.record, 'observations', prefix: 'Latest'),
    ];
  }

  static List<HandoffLine> _background(HandoffInput input) => <HandoffLine>[
        _lineFrom(input.record, 'allergies'),
        _lineFrom(input.record, 'problems'),
        _lineFrom(input.record, 'medications'),
        _lineFrom(input.record, 'activity'),
      ];

  static List<HandoffLine> _assessment(HandoffInput input) {
    if (input.concerns.isEmpty) {
      return const <HandoffLine>[
        HandoffLine(text: 'No deteriorating trends or red flags noted.'),
      ];
    }
    return <HandoffLine>[
      for (final concern in input.concerns)
        HandoffLine(text: concern, severity: FlagSeverity.caution),
    ];
  }

  static List<HandoffLine> _recommendation(HandoffInput input) {
    if (input.outstanding.isEmpty) {
      return const <HandoffLine>[HandoffLine(text: 'No outstanding tasks.')];
    }
    return <HandoffLine>[
      for (final task in input.outstanding) HandoffLine(text: task),
    ];
  }

  /// Turns a record-summary line into a handoff line, preserving its state and
  /// tone so "Not recorded" carries through the handoff unchanged.
  static HandoffLine _lineFrom(RecordSummary record, String key,
      {String? prefix}) {
    final section = record.sections.firstWhere((s) => s.key == key);
    final item = section.items.first;
    final label = prefix == null ? item.label : '$prefix ${_lower(item.label)}';
    return HandoffLine(
      text: '$label: ${item.value}',
      state: item.state,
      severity: item.severity,
    );
  }

  static String _lower(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}
