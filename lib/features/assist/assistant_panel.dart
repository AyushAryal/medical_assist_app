import 'package:flutter/material.dart';

import '../../ai/pipeline.dart';
import '../../ai/presentation.dart';
import '../../ai/cohort/assist_reply.dart';
import '../../ai/cohort/query_vocabulary.dart';
import '../../core/design/design.dart';
import 'presentation_view.dart';

/// One turn in the conversation.
typedef AssistantTurn = ({
  bool fromUser,
  String text,
  List<String> suggestions,
});

/// The assistant's conversation surface.
///
/// Takes its behaviour as callbacks rather than reaching for providers, so it
/// can be driven by a test. That is not gold-plating: the text field in here
/// was reported broken three times, and each fix was a guess because there was
/// no way to reproduce it below the level of a running phone. It is testable
/// now, and the properties that kept breaking are asserted in
/// `test/features/assistant_panel_test.dart`.
class AssistantPanel extends StatefulWidget {
  const AssistantPanel({
    super.key,
    required this.onAsk,
    required this.onClose,
    required this.onExpand,
    required this.greeting,
    required this.guide,
    this.history = const <AssistantTurn>[],
    this.onStartAfresh,
    this.onGuide,
    this.onSpeak,
    this.onStopListening,
    this.onCancelListening,
    this.isListening = false,
    this.level = 0,
  });

  /// Answers a question. Everything that needs a database lives behind this.
  final Future<AssistResult> Function(String question) onAsk;

  final VoidCallback onClose;

  /// Opens the full screen, carrying the last question across.
  final ValueChanged<String> onExpand;

  final AssistReply greeting;

  /// The conversation so far, replayed on open.
  ///
  /// The thread lives in the pipeline, shared with the full page — so closing
  /// this panel, or asking on the page instead, loses nothing. A panel that
  /// greeted you from scratch every time was a search box wearing a chat's
  /// clothes.
  final List<AssistantTurn> history;

  /// Clears the shared thread. Offered in the header once there is one,
  /// because a conversation the user cannot end is a context they cannot
  /// escape — every fragment they type keeps refining a question they have
  /// moved on from.
  final VoidCallback? onStartAfresh;

  /// What the (i) opens: which words search which table.
  final MetricExplanation guide;

  /// Opens the full capability list, and returns what was tapped.
  ///
  /// Handed in rather than opened from here, because this panel is mounted
  /// above the router's Navigator so that it can float over every screen —
  /// which leaves its own context with no Navigator in it, and
  /// `showModalBottomSheet` throws there. The owner has the root navigator; it
  /// does the opening and hands back the choice.
  final Future<String?> Function()? onGuide;

  /// True while the microphone is live. The panel shows the waveform itself
  /// rather than handing off to a sheet — a modal that covers the conversation
  /// you are dictating into is a strange place to put a microphone.
  final bool isListening;

  /// Live input level, 0–1, for the waveform.
  final double level;

  /// Dictates a question, returning the transcript. Null disables the control.
  final VoidCallback? onSpeak;

  /// Ends dictation and transcribes what was said.
  final VoidCallback? onStopListening;

  /// Abandons dictation without transcribing.
  final VoidCallback? onCancelListening;

  @override
  State<AssistantPanel> createState() => AssistantPanelState();
}

/// Public so the host can hand a finished transcript back in. The recorder
/// lives outside the panel — it must survive the panel closing mid-recording.
class AssistantPanelState extends State<AssistantPanel> {
  final TextEditingController _question = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  final List<AssistantTurn> _turns = <AssistantTurn>[];
  AssistResult? _result;
  bool _running = false;
  String _lastQuestion = '';

  /// Bumped after every submitted question, and used as the field's key.
  ///
  /// This is the fix for text coming back from the dead. Clearing a controller
  /// only changes Flutter's side of the story: the platform keyboard keeps its
  /// own buffer, and on Android it re-sends that buffer whenever the input
  /// connection is re-established — so the question just asked reappeared over
  /// the next one being typed, and characters deleted before a reconnection
  /// came back with it. Changing the key retires the old connection outright,
  /// which is the only way to be sure nothing survives it.
  int _generation = 0;

  /// The question just submitted, held so the platform keyboard replaying it
  /// can be recognised and dropped.
  ///
  /// This was a *timed* window and that was the flaw: the replay does not
  /// arrive on a schedule, it arrives when the input connection is next
  /// established — which is usually when the field is tapped again, long after
  /// any reasonable window has closed. So the guard now lasts until the person
  /// does something, not until a clock runs out.
  ///
  /// What distinguishes the two: a replay puts the *entire* previous question
  /// back in one step, from an empty box. A person typing produces a first
  /// character, which differs from the guarded text and releases the guard
  /// immediately — so retyping the same question by hand still works. Only a
  /// single-step jump to exactly the previous text is treated as the keyboard
  /// talking, and that is precisely what a replay is.
  String? _replayGuard;

  /// Whether the box had text at the last rebuild, so the clear control can
  /// appear and disappear with it.
  bool _hadText = false;

  void _onControllerChanged() {
    final guarded = _replayGuard;
    final text = _question.text;

    if (guarded != null) {
      if (text == guarded) {
        // The whole previous question, back in one step. Keep guarding: some
        // keyboards replay more than once.
        _question.clear();
        return;
      }
      if (text.isNotEmpty) {
        // Someone is typing. Release.
        _replayGuard = null;
      }
    }

    // Rebuild only when emptiness changes, not on every keystroke: the clear
    // control's presence is the only thing that depends on it, and rebuilding
    // a conversation transcript per character would be wasteful.
    final hasText = _question.text.isNotEmpty;
    if (hasText != _hadText && mounted) {
      setState(() => _hadText = hasText);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.history.isEmpty) {
      _turns.add((
        fromUser: false,
        text: widget.greeting.text,
        suggestions: widget.greeting.suggestions,
      ));
    } else {
      _turns.addAll(widget.history);
      _lastQuestion = widget.history
          .lastWhere((t) => t.fromUser, orElse: () => widget.history.last)
          .text;
    }
    _question.addListener(_onControllerChanged);
    // Focus explicitly rather than with `autofocus`, so there is exactly one
    // thing deciding when this field takes focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _question.removeListener(_onControllerChanged);
    _question.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Puts a suggestion in the box for editing rather than running it.
  ///
  /// A suggested prompt is a starting point, not a command. Firing it
  /// immediately means the one thing people reliably want to do with a
  /// suggestion — narrow it, add a date, change the drug — costs them retyping
  /// the whole line. The cursor lands at the end, so adding to it is the
  /// default and running it unchanged is one more tap.
  void _compose(String suggestion) {
    // Deliberate input, so the replay guard must not eat it.
    _replayGuard = null;
    setState(() {
      _generation++;
      _question.value = TextEditingValue(
        text: suggestion,
        selection: TextSelection.collapsed(offset: suggestion.length),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<void> _ask(String question) async {
    final text = question.trim();
    if (text.isEmpty || _running) return;

    _replayGuard = text;

    setState(() {
      _generation++;
      _question.clear();
      _lastQuestion = text;
      _turns.add((
        fromUser: true,
        text: text,
        suggestions: const <String>[],
      ));
      _result = null;
      _running = true;
    });
    _scrollToEnd();

    final answer = await widget.onAsk(text);
    if (!mounted) return;

    setState(() {
      _result = answer;
      _running = false;
      // The transcript keeps the spoken line; the rendered answer sits below
      // it. Both come from the same result, so they cannot disagree.
      _turns.add((
        fromUser: false,
        text: answer.presentation.headline,
        suggestions: switch (answer.presentation) {
          MessagePresentation(:final suggestions) => suggestions,
          _ => const <String>[],
        },
      ));
    });
    _scrollToEnd();
    // The keyboard stays up between questions; asking a follow-up is the
    // normal next action, not the exception.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _clear() {
    _replayGuard = null;
    setState(() {
      _generation++;
      _question.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  /// Puts a dictated question in the box, ready to be edited or sent.
  void acceptTranscript(String transcript) {
    if (transcript.trim().isEmpty) return;
    _compose(transcript.trim());
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final size = MediaQuery.sizeOf(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 380,
        // Never more than half the screen: this is a panel over someone's
        // work, and covering that work is how it becomes a nuisance.
        maxHeight: size.height * 0.52,
      ),
      child: AiGlowBorder(
        active: _running,
        child: GlassPanel(
          padding: EdgeInsets.all(m.spaceMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _header(context),
              Flexible(
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(vertical: m.spaceSm),
                  children: <Widget>[
                    for (final turn in _turns) _bubble(context, turn),
                    // Only over the greeting. An empty panel with a blinking
                    // cursor asks a question of its own — "what can I say to
                    // this?" — and most people answer it by closing the panel.
                    if (_turns.length <= 1 && _result == null && !_running)
                      _starters(context),
                    if (_running)
                      Padding(
                        padding: EdgeInsets.only(top: m.spaceXs),
                        child: const AiTextPlaceholder(lines: 1),
                      ),
                    if (!_running && _result != null) _answer(context),
                  ],
                ),
              ),
              SizedBox(height: m.spaceXs),
              if (widget.isListening)
                _listeningStrip(context)
              else
                _input(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final m = context.metrics;

    return Row(
      children: <Widget>[
        const AiSparkleIcon(size: 18),
        SizedBox(width: m.spaceSm),
        Expanded(child: Text('Assistant', style: context.texts.labelLarge)),
        // Lost when this panel was extracted, which is exactly the kind of
        // thing extraction loses. Anything the app worked out for itself
        // carries one of these; a search that cannot say what it understands
        // is a guessing game.
        if (widget.onGuide != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'What you can ask',
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            onPressed: () async {
              final chosen = await widget.onGuide!();
              // Into the box, not straight to an answer — the version anyone
              // wants is usually a narrowed one.
              if (chosen != null && mounted) _compose(chosen);
            },
          )
        else
          InfoDot(
            explanation: widget.guide,
            semanticLabel: 'Which words search which table',
          ),
        if (widget.onStartAfresh != null && _turns.length > 1)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'New topic — forget this conversation',
            icon: const Icon(Icons.restart_alt, size: 18),
            onPressed: () {
              widget.onStartAfresh!();
              setState(() {
                _turns
                  ..clear()
                  ..add((
                    fromUser: false,
                    text: widget.greeting.text,
                    suggestions: widget.greeting.suggestions,
                  ));
                _result = null;
                _lastQuestion = '';
              });
            },
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Open the full search',
          icon: const Icon(Icons.open_in_full, size: 18),
          onPressed: () => widget.onExpand(
            _lastQuestion.isEmpty ? _question.text : _lastQuestion,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Close',
          icon: const Icon(Icons.close, size: 18),
          onPressed: widget.onClose,
        ),
      ],
    );
  }

  Widget _bubble(BuildContext context, AssistantTurn turn) {
    final m = context.metrics;
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceSm),
      child: Column(
        crossAxisAlignment:
            turn.fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          // A question you asked is tappable, and tapping it puts it back in
          // the box to be refined. Refining the last attempt is the normal way
          // anyone uses a search like this, and without it that means retyping
          // the whole line.
          //
          // The bubble itself rather than a button beneath it: a separate row
          // per question adds up fast in a panel capped at half the screen,
          // and the first thing to be pushed out of view is the oldest
          // question — the one most likely to be worth going back to.
          Semantics(
            button: turn.fromUser,
            label: turn.fromUser ? 'Edit this question' : null,
            child: Material(
              color: turn.fromUser
                  ? palette.primaryContainer
                  : palette.surfaceMuted,
              borderRadius: BorderRadius.circular(m.radiusMd),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: turn.fromUser ? () => _compose(turn.text) : null,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.7,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: m.spaceMd,
                    vertical: m.spaceSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          turn.text,
                          style: context.texts.bodySmall?.copyWith(
                            color: turn.fromUser
                                ? palette.onPrimaryContainer
                                : null,
                          ),
                        ),
                      ),
                      if (turn.fromUser) ...<Widget>[
                        SizedBox(width: m.spaceXs),
                        Icon(
                          Icons.edit_outlined,
                          size: 12,
                          color: palette.onPrimaryContainer
                              .withValues(alpha: 0.65),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (turn.suggestions.isNotEmpty) ...<Widget>[
            SizedBox(height: m.spaceXs),
            Wrap(
              spacing: m.spaceXs,
              runSpacing: m.spaceXs,
              children: <Widget>[
                for (final suggestion in turn.suggestions)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.north_west, size: 13),
                    label: Text(suggestion, style: context.texts.labelSmall),
                    tooltip: 'Put this in the box to edit',
                    onPressed: () => _compose(suggestion),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// One question from each thing this can do.
  ///
  /// Four chips rather than the full list on the Ask page: this panel opens
  /// over someone's work and is not the place to teach a feature in depth. It
  /// is the place to show that the feature exists, in words that work — each
  /// of these is answered without help, and tapping one loads it for editing
  /// rather than firing it, because the useful version is almost always a
  /// narrowed version.
  Widget _starters(BuildContext context) {
    final m = context.metrics;

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceSm),
      child: Wrap(
        spacing: m.spaceXs,
        runSpacing: m.spaceXs,
        children: <Widget>[
          for (final group in QueryVocabulary.starters.take(4))
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.north_west, size: 13),
              label: Text(
                group.starters.first,
                style: context.texts.labelSmall,
              ),
              tooltip: group.reason,
              onPressed: () => _compose(group.starters.first),
            ),
        ],
      ),
    );
  }

  /// Dictation, inside the panel.
  ///
  /// The previous version raised the full dictation sheet, which slid a modal
  /// over the conversation the question was being asked about — and put a
  /// record/stop/discard flow in front of someone who wanted to say one
  /// sentence. A question is not a clinical note; it does not need the note's
  /// capture ceremony.
  Widget _listeningStrip(BuildContext context) {
    final m = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SiriWaveform(level: widget.level, active: true, height: 56),
        SizedBox(height: m.spaceXs),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Listening — say your question',
                style: context.texts.labelSmall,
              ),
            ),
            TextButton(
              onPressed: widget.onStopListening,
              child: const Text('Done'),
            ),
            TextButton(
              onPressed: widget.onCancelListening,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  /// The answer, rendered by the same code the full screen uses.
  ///
  /// Previously this panel drew its own idea of a result and the full page drew
  /// another, and they drifted twice. One renderer means a result reads the
  /// same wherever it is shown, and a new kind of output appears in both places
  /// at once.
  Widget _answer(BuildContext context) {
    final result = _result!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AssistPresentationView(
          presentation: result.presentation,
          provenance: result.provenance,
          isGenerated: result.isGenerated,
          compact: true,
          // The assistant's bubble above already said it.
          showHeadline: false,
          onSuggestion: _compose,
          followUps: result.followUps,
          onFollowUp: (followUp) => _ask(followUp.text),
          onExpand: () => widget.onExpand(_lastQuestion),
        ),
        if (result.secondary case final secondary?) ...<Widget>[
          SizedBox(height: context.metrics.spaceSm),
          AssistPresentationView(
            presentation: secondary,
            provenance: result.provenance,
            compact: true,
            onExpand: () => widget.onExpand(_lastQuestion),
          ),
        ],
      ],
    );
  }

  Widget _input(BuildContext context) {
    return TextField(
      // Retires the platform input connection after every question — see the
      // note on [_generation].
      key: ValueKey<int>(_generation),
      controller: _question,
      focusNode: _focus,
      textInputAction: TextInputAction.send,
      // Both off, and not as a preference. A query is drug names, surnames and
      // clinical terms — precisely the words a phone keyboard is most confident
      // about "correcting".
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      // The decisive one. `autocorrect: false` is a *hint*, and several
      // keyboards ignore it and keep composing anyway — and it is the
      // composing buffer that gets replayed, which is what put deleted
      // characters back on screen as the user typed. This keyboard type turns
      // the composing machinery off outright.
      //
      // The cost is real and worth stating: some keyboards drop swipe typing
      // and the emoji key in this mode. For a box whose contents are drug
      // names and surnames, a keyboard that does not try to help is the
      // better trade.
      keyboardType: TextInputType.visiblePassword,
      onSubmitted: _ask,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Ask a question…',
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Only once there is something to clear, so it does not sit there
            // as a permanent third control competing with send.
            if (_question.text.isNotEmpty)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Clear',
                icon: const Icon(Icons.close, size: 18),
                onPressed: _clear,
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: widget.onSpeak == null
                  ? 'Install a speech model in Settings › Dictation to ask by '
                      'voice'
                  : 'Ask by voice',
              icon: Icon(
                Icons.mic_none_outlined,
                size: 20,
                color: widget.onSpeak == null
                    ? context.palette.onSurfaceMuted.withValues(alpha: 0.4)
                    : null,
              ),
              onPressed: widget.onSpeak,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Send',
              icon: const Icon(Icons.arrow_upward, size: 20),
              onPressed: () => _ask(_question.text),
            ),
          ],
        ),
      ),
    );
  }
}
