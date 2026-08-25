import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../ai/assist_request.dart';
import '../../ai/cohort/assist_reply.dart';
import '../../ai/cohort/query_vocabulary.dart';
import 'assistant_panel.dart';
import 'capability_sheet.dart';
import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../../core/routing/app_router.dart';

/// Comfortably above the 48dp minimum tap target — this gets pressed with a
/// thumb, sometimes gloved.
const double _bubbleDiameter = 56;

/// Breathing room around the orb for its own glow.
///
/// The shadow is drawn outside the 56px circle, so with the bubble flush
/// against the edge of its container the halo was sliced off on that side —
/// which read as a rendering fault rather than as a design. Reserving the
/// space keeps the glow whole in every resting position.
const double _bubbleHalo = 14;

/// The assistant bubble that follows the clinician across every screen.
///
/// A bubble rather than a tab because the questions it answers arrive *during*
/// other work — mid-consultation, someone wonders whether this patient is one
/// of the forty on warfarin. Making them leave the chart to find out is how a
/// feature goes unused.
///
/// Three deliberate limits:
///
/// * **It never covers an action.** It sits clear of the navigation bar and of
///   any floating action button, because a clinical screen's own controls
///   outrank it.
/// * **It can be turned off** from Settings. A control that follows someone
///   onto every screen has to be removable, or the people it does not suit
///   spend the day working around it.
/// * **It answers by opening the full screen.** No inline result: an answer
///   worth acting on needs its filters shown beside it, and a bubble is too
///   small to show those honestly.
///
/// It navigates through [AppRouter.rootNavigatorKey] rather than through its
/// own `BuildContext`. That is not incidental: to float above *every* screen it
/// is mounted in `MaterialApp.router`'s builder, which sits above the router's
/// Navigator — so its context has neither a `GoRouter` nor a `Navigator` in it,
/// and both `context.push` and `showModalBottomSheet` throw there. The root
/// navigator key is the app's own handle on the tree below.
class FloatingAssistant extends StatefulWidget {
  const FloatingAssistant({super.key, required this.child});

  final Widget child;

  @override
  State<FloatingAssistant> createState() => _FloatingAssistantState();
}

class _FloatingAssistantState extends State<FloatingAssistant> {
  final GlobalKey<AssistantPanelState> _panelKey =
      GlobalKey<AssistantPanelState>();

  bool _open = false;
  bool _listening = false;

  /// Where the collapsed bubble sits, as a fraction of the free space.
  ///
  /// Draggable because there is no safe place to put it. Whatever corner it
  /// defaults to, it will sooner or later sit on top of the one control
  /// someone needs — a Sign note button, a patient at the bottom of a list,
  /// the field they are typing into. Rather than guess, let it be moved.
  Alignment _bubbleAt = Alignment.bottomRight;

  /// The bubble's alignment while a drag is live, tracking the finger
  /// directly with no animation. Null when not dragging, which is also what
  /// [_dragging] tests.
  ///
  /// Kept separate from [_bubbleAt] rather than overwriting it on every
  /// pointer move: [_bubbleAt] is the *rested* position the bubble returns to
  /// on the next launch and after `_open` closes, and a drag that is
  /// abandoned mid-gesture must not have already overwritten it before the
  /// release logic decides where to snap.
  Alignment? _liveAlignment;

  bool get _dragging => _liveAlignment != null;

  /// The area the bubble is positioned within — the same box [AnimatedAlign]
  /// is laid out in — captured each build via [LayoutBuilder] so drag deltas
  /// (pixels) can be converted to alignment deltas (a -1..1 fraction of it).
  Size? _dragAreaSize;

  void _onBubbleDragStart() {
    // Starts exactly where the bubble is currently resting, so the first
    // frame of the drag has nothing to jump from.
    setState(() => _liveAlignment = _bubbleAt);
  }

  void _onBubbleDragUpdate(Offset delta) {
    final area = _dragAreaSize;
    final live = _liveAlignment;
    if (area == null || live == null) return;
    // Alignment's -1..1 spans (containerSize - childSize), not the raw
    // container size, so a pixel delta has to be scaled by half of the free
    // space, not half of the area itself, to track the finger 1:1.
    final freeWidth = area.width - _bubbleDiameter;
    final freeHeight = area.height - _bubbleDiameter;
    final dx = freeWidth <= 0 ? 0.0 : delta.dx / (freeWidth / 2);
    final dy = freeHeight <= 0 ? 0.0 : delta.dy / (freeHeight / 2);
    setState(() {
      _liveAlignment = Alignment(
        (live.x + dx).clamp(-1.0, 1.0),
        (live.y + dy).clamp(-1.0, 1.0),
      );
    });
  }

  void _onBubbleDragEnd() {
    final live = _liveAlignment;
    if (live == null) return;
    // Clearing `_liveAlignment` and setting `_bubbleAt` in the same setState
    // hands the bubble straight from live tracking to the eased snap — the
    // same `AnimatedAlign` instance carries its current on-screen position
    // forward as the animation's start point, so it glides on from wherever
    // it actually was released instead of reappearing at the old resting
    // spot first.
    setState(() {
      _bubbleAt = _snapAlignment(live);
      _liveAlignment = null;
    });
  }

  /// Snaps a live drag position to one of six resting places: left or right,
  /// crossed with top, middle or bottom third of the area it moves within.
  ///
  /// Free positioning sounds friendlier and is worse: a bubble left at an
  /// arbitrary offset drifts under the status bar, half off the edge, or on
  /// top of the navigation bar, and it has to be rescued. Snapping to a side
  /// keeps every resting place a usable one.
  Alignment _snapAlignment(Alignment live) {
    final x = live.x < 0 ? -1.0 : 1.0;
    final y = switch (live.y) {
      < -1 / 3 => -1.0,
      < 1 / 3 => 0.0,
      _ => 1.0,
    };
    return Alignment(x, y);
  }

  /// Starts dictation inside the panel.
  ///
  /// Reuses the same recorder and the same on-device transcription as note
  /// dictation — a second, subtly different voice path would be two things to
  /// keep working and two places to get privacy wrong — but not the same
  /// *screen*. The note flow raises a modal with a record/stop/discard
  /// ceremony, which is right for evidence attached to a record and wrong for
  /// saying one sentence into a search box.
  Future<void> _startListening() async {
    final recorder = context.read<AppBootstrap>().dictation;
    final started = await recorder.start();
    if (!mounted || !started) return;
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
      // Into the box rather than straight to a search: a misheard question
      // that runs itself is harder to recover from than one you can correct.
      _panelKey.currentState?.acceptTranscript(result.text);
    } on Object {
      // Nothing usable. The panel keeps whatever was typed; saying so in a
      // dialog over a search box would be more disruptive than the failure.
    } finally {
      await capture.file.delete().catchError((_) => capture.file);
    }
  }

  Future<void> _cancelListening() async {
    await context.read<AppBootstrap>().dictation.cancel();
    if (mounted) setState(() => _listening = false);
  }

  /// Raises the capability list from the root navigator.
  Future<String?> _openGuide() async {
    final target = AppRouter.rootNavigatorKey.currentContext;
    if (target == null || !target.mounted) return null;
    return CapabilitySheet.show(target);
  }

  Future<void> _submit(String question) async {
    setState(() => _open = false);
    final target = AppRouter.rootNavigatorKey.currentContext;
    if (target == null || !target.mounted) return;
    final bootstrap = target.read<AppBootstrap>();

    // If the page is being opened onto the conversation's own last question,
    // it adopts the answer already computed instead of re-running it — the
    // thread is shared, so expanding is a change of window, not a new ask.
    final thread = bootstrap.pipeline.thread;
    if (question.trim().isEmpty || question.trim() == thread.lastQuestion) {
      await target.push(Routes.ask);
      return;
    }
    await target.push('${Routes.ask}?q=${Uri.encodeComponent(question)}');
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = context.watch<AppBootstrap>();
    if (!bootstrap.isReady || !bootstrap.assistantEnabled) return widget.child;

    final m = context.metrics;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Stack(
      children: <Widget>[
        widget.child,
        Positioned.fill(
          // Ride above the keyboard. A panel anchored to a fixed offset is
          // simply invisible the moment its own text field is focused, which
          // is the one moment it is certainly being used.
          bottom: keyboard > 0
              ? keyboard + m.spaceMd
              : (context.breakpoint.isCompact ? m.space2xl * 3 : m.space2xl),
          top: m.space2xl * 2,
          left: m.spaceLg,
          right: m.spaceLg,
          // Route changes are listened to *here*, never around `widget.child`.
          // That child is the router's own Navigator, and rebuilding it from a
          // router notification tears a navigator down mid-navigation — the
          // framework reports it as "_CustomNavigator must not be deactivated
          // when in _ElementLifecycle.failed state" and the screen goes red.
          child: ListenableBuilder(
            listenable:
                AppRouter.instance?.routerDelegate ?? const _NeverNotifies(),
            builder: (context, _) {
              final path =
                  AppRouter
                      .instance
                      ?.routerDelegate
                      .currentConfiguration
                      .uri
                      .path ??
                  '';
              // A bubble that opens a small version of the page you are
              // already looking at is clutter, and here it sat directly on top
              // of that page's send button.
              if (path.startsWith(Routes.ask)) {
                return const SizedBox.shrink();
              }

              return SafeArea(
                top: false,
                // A local Overlay. Mounting above the router's Navigator is
                // what lets this float over every screen, and it is also what
                // leaves it with no Overlay of its own — so every tooltip in
                // here threw "No Overlay widget found" and the bubble rendered
                // as a red error box, and `Draggable` had nowhere to put its
                // feedback.
                child: Overlay(
                  initialEntries: <OverlayEntry>[
                    OverlayEntry(
                      // Explicitly filled. An overlay lays a non-positioned
                      // child out with loose constraints, so a bare `Align`
                      // shrink-wraps to the bubble and has nothing left to
                      // align *within* — the bubble ended up stranded
                      // mid-screen instead of in the corner it was asked for.
                      builder: (context) => Positioned.fill(
                        // Measures the box `AnimatedAlign` below is laid out
                        // in, so drag handlers can convert pixel deltas into
                        // alignment deltas. A plain assignment, not a
                        // `setState` — capturing it is a side effect of
                        // layout, not a change that itself needs a rebuild.
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            _dragAreaSize = constraints.biggest;
                            return AnimatedAlign(
                              // Glides to the edge rather than teleporting.
                              // Snapping is right — a bubble dropped at an
                              // arbitrary offset drifts under the status bar
                              // or half off the screen — but an instant jump
                              // reads as the control being yanked out of your
                              // hand. Zero duration while a drag is live: the
                              // bubble must track the finger exactly, and
                              // only the release should ease — using the same
                              // `AnimatedAlign` for both (rather than a plain
                              // `Align` while dragging) is what lets the
                              // eased snap continue from wherever the bubble
                              // actually was on release instead of jumping
                              // back to its old resting spot first.
                              duration: _dragging
                                  ? Duration.zero
                                  : const Duration(milliseconds: 450),
                              // `easeOutCubic` rather than `easeOutBack`:
                              // back's overshoot-then-settle is what read as
                              // a snap, not a glide — a plain decelerate
                              // covers the same "arriving, not landing" feel
                              // without it.
                              curve: Curves.easeOutCubic,
                              alignment: _open
                                  ? Alignment.bottomRight
                                  : (_liveAlignment ?? _bubbleAt),
                              child: _open
                                  ? ListenableBuilder(
                                      listenable: bootstrap.dictation,
                                      builder: (context, _) => AssistantPanel(
                                        key: _panelKey,
                                        greeting: AssistReplies.greeting(),
                                        // Replay the shared thread, so the panel
                                        // reopens mid-conversation and the page
                                        // and bubble are two windows on one
                                        // dialogue.
                                        history: <AssistantTurn>[
                                          for (final turn
                                              in bootstrap
                                                  .pipeline
                                                  .thread
                                                  .turns) ...<AssistantTurn>[
                                            (
                                              fromUser: true,
                                              text: turn.question,
                                              suggestions: const <String>[],
                                            ),
                                            (
                                              fromUser: false,
                                              text: turn.headline,
                                              suggestions: const <String>[],
                                            ),
                                          ],
                                        ],
                                        onStartAfresh:
                                            bootstrap.pipeline.startAfresh,
                                        guide: QueryVocabulary.tableHint(),
                                        // Opened through the root navigator: this
                                        // panel sits above the router's own, so a
                                        // sheet raised from here has nowhere to
                                        // go.
                                        onGuide: _openGuide,
                                        // The one pipeline, shared with the full
                                        // search screen. This panel used to carry
                                        // its own copy of the middle of it.
                                        onAsk: (question) =>
                                            bootstrap.pipeline.ask(
                                              AssistRequest(
                                                text: question,
                                                source: RequestSource.typed,
                                                actor: bootstrap
                                                    .session
                                                    .signatureName,
                                                clinicId: bootstrap
                                                    .session
                                                    .activeClinic
                                                    ?.id,
                                              ),
                                            ),
                                        onSpeak: bootstrap.canTranscribe
                                            ? _startListening
                                            : null,
                                        onStopListening: _stopListening,
                                        onCancelListening: _cancelListening,
                                        isListening: _listening,
                                        level:
                                            bootstrap.dictation.level.current,
                                        onClose: () =>
                                            setState(() => _open = false),
                                        onExpand: _submit,
                                      ),
                                    )
                                  : _AssistBubble(
                                      dragging: _dragging,
                                      onTap: () => setState(() => _open = true),
                                      onDragStart: _onBubbleDragStart,
                                      onDragUpdate: _onBubbleDragUpdate,
                                      onDragEnd: _onBubbleDragEnd,
                                    ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A Listenable that never fires, for when the router is not available yet.
class _NeverNotifies extends Listenable {
  const _NeverNotifies();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// The collapsed state: a small sparkling orb.
///
/// Dragging is a raw pan gesture rather than [Draggable]: a [Draggable]
/// tracks the finger with a separate `feedback` ghost while the real bubble
/// sits inert (hidden behind `childWhenDragging`) at its old resting spot,
/// so on release the real bubble reappeared there for a frame before easing
/// to the new one — a visible jump backwards before the snap forwards. This
/// widget *is* the thing that moves, reporting each delta up to
/// [_FloatingAssistantState], which is what lets the eased snap on release
/// continue from wherever it actually was.
class _AssistBubble extends StatelessWidget {
  const _AssistBubble({
    required this.onTap,
    required this.dragging,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final VoidCallback onTap;

  /// Whether a drag is currently live — brightens the glow, matching the
  /// old `feedback` ghost's dragging look.
  final bool dragging;

  final VoidCallback onDragStart;

  /// Raw pointer movement since the last update, in pixels.
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ask about the register. Drag to move.',
      child: GestureDetector(
        onPanStart: (_) => onDragStart(),
        onPanUpdate: (details) => onDragUpdate(details.delta),
        onPanEnd: (_) => onDragEnd(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: _orb(context, dragging: dragging),
          ),
        ),
      ),
    );
  }

  Widget _orb(BuildContext context, {bool dragging = false}) {
    final m = context.metrics;
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.all(_bubbleHalo),
      child: AiGlowBorder(
        active: true,
        borderRadius: BorderRadius.circular(_bubbleDiameter / 2),
        strokeWidth: 2,
        child: Container(
          width: _bubbleDiameter,
          height: _bubbleDiameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.surface,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: palette.accent.withValues(alpha: dragging ? 0.5 : 0.28),
                blurRadius: dragging ? m.shadowBlur * 1.5 : m.shadowBlur,
                offset: Offset(0, m.shadowOffsetY / 2),
              ),
            ],
          ),
          child: const AiSparkleIcon(size: 24),
        ),
      ),
    );
  }
}
