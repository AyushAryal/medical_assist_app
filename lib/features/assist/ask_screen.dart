import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ai/assist_request.dart';
import '../../ai/pipeline.dart';
import '../../core/design/design.dart';
import '../../core/smart_phrases/smart_phrase.dart';
import '../../core/smart_phrases/smart_phrase_library.dart';
import '../../data/repositories/clinical_repository.dart';
import 'ask_intro.dart';
import 'capability_sheet.dart';
import 'composer.dart';
import 'presentation_view.dart';
import '../../core/app_bootstrap.dart';

/// Ask a question about the register, in words or with filters.
///
/// The safety property this screen exists to hold: **no SQL is ever generated
/// from what is typed.** A phrase is matched onto a set of filters that a human
/// wrote and a test suite checks, the filters are shown back on every result,
/// and the query that runs is one of a handful of hand-written statements.
///
/// That matters more here than anywhere else in the app. A wrong transcript is
/// read by the clinician who dictated it; a wrong recall list is not read by
/// anybody, because the entire reason for running it is that nobody could
/// assemble it by hand. A list that quietly misses three patients looks exactly
/// like a correct one.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key, this.initialQuestion});

  /// A question handed over by the floating assistant, run on open.
  final String? initialQuestion;

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final SmartPhraseController _question = SmartPhraseController();
  final FocusNode _focus = FocusNode();

  /// Dynamic macros plus the clinic's saved text phrases. Starts with the
  /// code macros and gains the database ones once they load.
  SmartPhraseRegistry _registry = buildSmartPhraseRegistry(const []);

  bool _hasText = false;

  /// The last question actually sent, shown discreetly above the composer so
  /// what produced the answer on screen is never in doubt.
  String? _lastAsked;

  /// True while the microphone is live. The page shows the waveform where the
  /// input row was, rather than raising a modal over the answer being read.
  bool _listening = false;

  AssistResult? _result;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _question.addListener(() {
      final hasText = _question.text.isNotEmpty;
      if (hasText != _hasText && mounted) setState(() => _hasText = hasText);
    });
    // Redraws the composer's glow when focus changes. The border lights while
    // the field is live, which is the one moment a flourish is telling the
    // reader something rather than decorating.
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPhrases());
    final seeded = widget.initialQuestion;
    final pipeline = context.read<AppBootstrap>().pipeline;
    if (seeded != null &&
        seeded.trim().isNotEmpty &&
        seeded.trim() != pipeline.thread.lastQuestion) {
      _question.text = seeded;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask(seeded));
    } else if (pipeline.lastResult case final adopted?) {
      // Opened onto an existing conversation — from the bubble, or by
      // returning to the tab. The answer on screen is the one already
      // computed; the thread is shared, so this page continues the dialogue
      // rather than starting a parallel one.
      _result = adopted;
      _lastAsked = pipeline.thread.lastQuestion;
    }
  }

  @override
  void dispose() {
    _question.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Loads an example into the box for editing rather than running it. See the
  /// note on the assistant panel: a suggestion is a starting point.
  /// Dictates a question rather than typing it.
  ///
  /// The bubble had this and the full page did not, which is backwards: the
  /// full page is where longer questions get asked. Same recorder, same
  /// on-device transcription as note dictation.
  Future<void> _startListening() async {
    final messenger = ScaffoldMessenger.of(context);
    final started = await context.read<AppBootstrap>().dictation.start();
    if (!mounted) return;
    if (!started) {
      // Silence here would be indistinguishable from a broken button.
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'The microphone is not available. Check that this app has '
            'permission to use it.',
          ),
        ),
      );
      return;
    }
    setState(() => _listening = true);
  }

  Future<void> _stopListening() async {
    final bootstrap = context.read<AppBootstrap>();
    final capture = await bootstrap.dictation.stop();
    if (!mounted) return;
    setState(() => _listening = false);
    if (capture == null) return;

    try {
      final result = await bootstrap.transcription.transcribe(capture.file);
      if (!mounted) return;
      // Into the box, not straight to a search: a misheard question that runs
      // itself is harder to recover from than one you can correct.
      _compose(result.text);
    } on Object {
      // Nothing usable; the box keeps whatever was already typed.
    } finally {
      await capture.file.delete().catchError((_) => capture.file);
    }
  }

  Future<void> _cancelListening() async {
    await context.read<AppBootstrap>().dictation.cancel();
    if (mounted) setState(() => _listening = false);
  }

  void _clear() {
    // Ends the topic, not just the text: the ✕ on the context strip is the
    // way out of a conversation, and a cleared screen that secretly keeps
    // refining old filters would be worse than no memory at all.
    context.read<AppBootstrap>().pipeline.startAfresh();
    setState(() {
      _question.clear();
      _result = null;
      _lastAsked = null;
    });
    _focus.requestFocus();
  }

  /// Opens the guide, and loads whatever was tapped into the box.
  ///
  /// Into the box rather than straight to an answer: a suggestion is a starting
  /// point, and the version anyone actually wants is usually narrowed — a date
  /// added, a drug changed. Running it immediately makes that cost a retype.
  Future<void> _openCapabilities() async {
    final chosen = await CapabilitySheet.show(context);
    if (chosen != null && mounted) _compose(chosen);
  }

  void _compose(String example) {
    setState(() {
      _question.value = TextEditingValue(
        text: example,
        selection: TextSelection.collapsed(offset: example.length),
      );
    });
    _focus.requestFocus();
  }

  /// Loads the clinic's saved text phrases and folds them into the registry.
  /// The built-in macros stand alone if the read fails.
  Future<void> _loadPhrases() async {
    try {
      final records = await context
          .read<ClinicalRepository>()
          .smartPhrases
          .all();
      if (mounted) {
        setState(() => _registry = buildSmartPhraseRegistry(records));
      }
    } on Object {
      // Keep the built-in macros only.
    }
  }

  Future<void> _ask(String question) async {
    if (question.trim().isEmpty || _running) return;

    setState(() {
      _running = true;
      _result = null;
      _lastAsked = question.trim();
    });

    final bootstrap = context.read<AppBootstrap>();
    final result = await bootstrap.pipeline.ask(
      AssistRequest(
        text: question,
        source: RequestSource.typed,
        actor: bootstrap.session.signatureName,
        clinicId: bootstrap.session.activeClinic?.id,
        // The exact patient the `\pat` phrase resolved, if any — this is what
        // turns "how is X doing" into a lookup instead of a guess.
        patientId: _question.payloadOf('patient'),
      ),
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSpeak = context.watch<AppBootstrap>().canTranscribe;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Ask'),
        actions: <Widget>[
          IconButton(
            tooltip: 'What you can ask',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: _openCapabilities,
          ),
        ],
      ),
      body: ContentWidth.columns(
        child: Column(
          children: <Widget>[
            Expanded(child: _body(context)),
            // Input at the bottom while a conversation is on screen — but on
            // the empty page it starts mid-screen (see the riser below), the
            // way a prompt invites rather than hides.
            AskComposer(
              controller: _question,
              smartPhrases: _registry,
              focus: _focus,
              listening: _listening,
              hasText: _hasText,
              canSpeak: canSpeak,
              lastAsked: _lastAsked,
              contextSummary: context
                  .watch<AppBootstrap>()
                  .pipeline
                  .thread
                  .summary,
              onAsk: _ask,
              onClear: _clear,
              onStartListening: _startListening,
              onStopListening: _stopListening,
              onCancelListening: _cancelListening,
              onOpenGuide: _openCapabilities,
            ),
            // The riser: empty page → the composer floats at mid-height;
            // the moment an answer starts it eases down to the bottom and
            // stays there for the conversation.
            AnimatedContainer(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              height: _running || _result != null
                  ? 0
                  : MediaQuery.viewInsetsOf(context).bottom > 0
                  ? MediaQuery.sizeOf(context).height * 0.05
                  : MediaQuery.sizeOf(context).height * 0.28,
            ),
          ],
        ),
      ),
    );
  }

  /// The question this answer (or search) belongs to, pinned above it — an
  /// answer without its question is a number with no units.
  Widget? _askedHeader(BuildContext context) {
    final asked = _lastAsked;
    if (asked == null) return null;
    final m = context.metrics;
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.fromLTRB(m.spaceLg, m.spaceSm, m.spaceLg, m.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.chat_bubble_outline,
            size: 15,
            color: palette.onSurfaceMuted,
          ),
          SizedBox(width: m.spaceSm),
          Expanded(
            child: Text(
              asked,
              style: context.texts.bodyMedium?.copyWith(
                color: palette.onSurfaceMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final m = context.metrics;

    if (_running) {
      return Column(
        children: <Widget>[
          ?_askedHeader(context),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: _searchingCard(context),
              ),
            ),
          ),
        ],
      );
    }

    final result = _result;
    if (result == null) return AskIntro(onQuestion: _compose);

    return ListView(
      padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceLg),
      children: <Widget>[
        if (_askedHeader(context) case final header?)
          Padding(padding: EdgeInsets.zero, child: header),
        // The same renderer the floating panel uses, so an answer reads
        // identically wherever it is shown and a new kind of output appears in
        // both places at once.
        AssistPresentationView(
          presentation: result.presentation,
          provenance: result.provenance,
          isGenerated: result.isGenerated,
          onSuggestion: _compose,
          followUps: result.followUps,
          onFollowUp: (followUp) => _ask(followUp.text),
        ),
        if (result.secondary case final secondary?) ...<Widget>[
          SizedBox(height: m.spaceMd),
          AssistPresentationView(
            presentation: secondary,
            provenance: result.provenance,
          ),
        ],
      ],
    );
  }

  Widget _searchingCard(BuildContext context) {
    final m = context.metrics;
    return AiGlowBorder(
      active: true,
      child: Padding(
        padding: EdgeInsets.all(m.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const AiSparkleIcon(size: 18),
                SizedBox(width: m.spaceSm),
                Text('Searching', style: context.texts.labelLarge),
              ],
            ),
            SizedBox(height: m.spaceMd),
            const AiTextPlaceholder(lines: 3),
          ],
        ),
      ),
    );
  }
}
