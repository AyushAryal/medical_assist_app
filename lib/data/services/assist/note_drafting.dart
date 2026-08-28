import '../../../clinical/insights/note_sectioniser.dart';
import 'language_model.dart';

/// Why a draft was refused, in words a clinician can act on.
class DraftRefused implements Exception {
  const DraftRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// One placed sentence and who decided where it went.
///
/// The text is always the clinician's own — nothing here is generated. What
/// varies is *who filed it*: the deterministic rules, or the model on a
/// sentence the rules could not read. That distinction is the only thing a
/// reviewer of this sort needs to look harder at, so it is carried all the way
/// to the screen rather than flattened into a joined string.
typedef DraftSentence = ({String text, bool placedByModel});

/// A dictation sorted into SOAP sections, ready to preview.
class SoapDraft {
  const SoapDraft({
    required this.sections,
    required this.provenance,
    required this.engineName,
    required this.placed,
    required this.unplaced,
  });

  /// Section key (`subjective`…`plan`) to text, assembled from the
  /// clinician's own sentences. Only non-empty sections appear.
  final Map<String, String> sections;

  /// The same sections, sentence by sentence, each tagged with who placed it.
  /// Keyed and ordered identically to [sections]; the joined strings there are
  /// these sentences' text with a space between. Kept alongside rather than
  /// replacing [sections] because everything that *applies* a section wants the
  /// plain string, and only the review screen wants the breakdown.
  final Map<String, List<DraftSentence>> provenance;

  /// Who did the sorting, for the review screen to say.
  final String engineName;

  /// How many sentences found a home.
  final int placed;

  /// The sentences nothing could place, left for the clinician. They stay in
  /// the working notes rather than being guessed at — a sentence in the wrong
  /// section is worse than a sentence still waiting.
  final List<String> unplaced;

  bool get isEmpty => sections.isEmpty;
}

/// A plan reworded for the patient, ready to preview.
class InstructionsDraft {
  const InstructionsDraft({required this.text, required this.engineName});

  final String text;
  final String engineName;
}

/// Who sorted a note, when the app is asked to say so.
const String rulesEngineName = 'the note rules';

/// Sorts dictation into SOAP sections.
///
/// **The model never writes a word here.** It is shown the clinician's
/// sentences, numbered, and asked which section each number belongs to; the
/// sections are then assembled from the *original* sentences by index. That
/// makes invention structurally impossible rather than merely detected —
/// which matters, because the detection version of this shipped first and a
/// small model failed it immediately, turning "likely viral URI" (an
/// assessment) into "has a history of viral URI" and a paracetamol
/// prescription into "seeking advice on paracetamol". Both read plausibly.
/// Neither is what the clinician said.
///
/// The app's own rules ([NoteSectioniser]) run first and always. The model,
/// when installed, only decides the sentences the rules left unplaced — so
/// the feature works on every device, and installing a model makes it reach
/// further rather than making it exist.
abstract final class NoteDrafting {
  static const List<String> sectionKeys = <String>[
    'subjective',
    'objective',
    'assessment',
    'plan',
  ];

  /// The rules-only sort. Always available, no model required.
  static SoapDraft sortByRules(String text) {
    final sorted = NoteSectioniser.sort(text);
    return _assemble(sorted, engineName: rulesEngineName);
  }

  /// The rules, then the model on whatever they could not place.
  ///
  /// Falls back to the rules-only result on any model failure — a sort that
  /// half-works is worth more than a refusal, because the review screen shows
  /// exactly what it did and nothing is applied without a tap.
  static Future<SoapDraft> sortWithModel(
    LanguageModelEngine engine,
    String text,
  ) async {
    final sorted = NoteSectioniser.sort(text);
    final undecided = sorted.where((s) => s.section == null).toList();
    if (undecided.isEmpty) {
      return _assemble(sorted, engineName: rulesEngineName);
    }

    final assignments = await _askModel(engine, undecided);
    if (assignments.isEmpty) {
      return _assemble(sorted, engineName: rulesEngineName);
    }

    final merged = <SectionedSentence>[
      for (final sentence in sorted)
        if (sentence.section == null && assignments[sentence.index] != null)
          (
            index: sentence.index,
            text: sentence.text,
            section: assignments[sentence.index],
            confidence: 1,
          )
        else
          sentence,
    ];

    return _assemble(
      merged,
      engineName: '${engine.name} with $rulesEngineName',
      modelPlaced: assignments.keys.toSet(),
    );
  }

  /// Asks the model which section each unplaced sentence belongs to.
  ///
  /// The reply is parsed as numbers and nothing else; anything the model says
  /// that is not a recognised `SECTION: n, n` line is discarded, and a number
  /// outside the range of sentences offered is discarded too. The worst a
  /// confused model can do is place a sentence oddly — which the review
  /// screen shows, section by section, before anything is applied.
  static Future<Map<int, NoteSection>> _askModel(
    LanguageModelEngine engine,
    List<SectionedSentence> undecided,
  ) async {
    final numbered = <int, SectionedSentence>{
      for (var i = 0; i < undecided.length; i++) i + 1: undecided[i],
    };

    final answer = await engine.assignSentencesToSections(
      <String>[
        for (final entry in numbered.entries) '${entry.key}. ${entry.value.text}',
      ],
    );
    if (answer == null) return const <int, NoteSection>{};

    final out = <int, NoteSection>{};
    for (final line in answer.split(RegExp(r'[\n;]+'))) {
      final match = RegExp(
        r'\b(subjective|objective|assessment|plan)\b\s*[:\-]?\s*([\d,\s]+)',
        caseSensitive: false,
      ).firstMatch(line);
      if (match == null) continue;

      final section = NoteSection.values
          .firstWhere((s) => s.name == match.group(1)!.toLowerCase());
      for (final digits in match.group(2)!.split(RegExp(r'[^\d]+'))) {
        final number = int.tryParse(digits);
        final sentence = number == null ? null : numbered[number];
        // One sentence, one section: a later claim on the same number is
        // ignored rather than allowed to move it.
        if (sentence != null && !out.containsKey(sentence.index)) {
          out[sentence.index] = section;
        }
      }
    }
    return out;
  }

  /// Builds the sections from the original sentences, in the order spoken.
  ///
  /// [modelPlaced] is the set of sentence indices the model filed; everything
  /// else was filed by the rules. Empty for a rules-only sort.
  static SoapDraft _assemble(
    List<SectionedSentence> sorted, {
    required String engineName,
    Set<int> modelPlaced = const <int>{},
  }) {
    final grouped = <NoteSection, List<DraftSentence>>{};
    final unplaced = <String>[];
    for (final sentence in sorted) {
      if (sentence.section case final section?) {
        (grouped[section] ??= <DraftSentence>[]).add(
          (
            text: sentence.text,
            placedByModel: modelPlaced.contains(sentence.index),
          ),
        );
      } else {
        unplaced.add(sentence.text);
      }
    }

    return SoapDraft(
      sections: <String, String>{
        for (final section in NoteSection.values)
          if (grouped[section] case final lines?)
            section.key: lines.map((s) => s.text).join(' '),
      },
      provenance: <String, List<DraftSentence>>{
        for (final section in NoteSection.values)
          if (grouped[section] case final lines?) section.key: lines,
      },
      engineName: engineName,
      placed: sorted.length - unplaced.length,
      unplaced: unplaced,
    );
  }

/// Rewords a plan as instructions a patient can follow, or refuses.
  static Future<InstructionsDraft> patientInstructions(
    LanguageModelEngine engine,
    String plan,
  ) async {
    final source = plan.trim();
    if (source.isEmpty) {
      throw const DraftRefused('Write the plan first.');
    }

    final draft = await engine.plainLanguageInstructions(source);
    final text = draft.text.trim();

    if (text.isEmpty) {
      throw const DraftRefused('The model produced nothing.');
    }
    if (_tokens(text).difference(_tokens(source)).isEmpty &&
        text.length >= source.length) {
      // No new words and no shorter: it echoed the plan back. An echo is not
      // a translation, here as everywhere.
      throw const DraftRefused(
        'The model repeated the plan instead of rewording it.',
      );
    }
    if (text.length > source.length * 4 + 200) {
      throw const DraftRefused(
        'The model wrote far more than the plan says, which means it was '
        'inventing. Nothing was kept.',
      );
    }

    return InstructionsDraft(text: text, engineName: draft.engineName);
  }

  static Set<String> _tokens(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9. ]'), ' ')
      // A decimal point inside a dose survives; sentence punctuation dies.
      .replaceAll(RegExp(r'\.(?!\d)'), ' ')
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toSet();
}
