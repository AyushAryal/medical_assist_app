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
              final path = AppRouter
                      .instance?.routerDelegate.currentConfiguration.uri.path ??
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
                        child: AnimatedAlign(
                          // Glides to the edge rather than teleporting.
                          // Snapping is right — a bubble dropped at an
                          // arbitrary offset drifts under the status bar or
                          // half off the screen — but an instant jump reads as
                          // the control being yanked out of your hand.
                          duration: const Duration(milliseconds: 340),
                          curve: Curves.easeOutBack,
                          alignment:
                              _open ? Alignment.bottomRight : _bubbleAt,
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
                                          in bootstrap.pipeline.thread.turns)
                                        ...<AssistantTurn>[
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
                                        actor:
                                            bootstrap.session.signatureName,
                                        clinicId: bootstrap
                                            .session.activeClinic?.id,
                                      ),
                                    ),
                                    onSpeak: bootstrap.canTranscribe
                                        ? _startListening
                                        : null,
                                    onStopListening: _stopListening,
                                    onCancelListening: _cancelListening,
                                    isListening: _listening,
                                    level: bootstrap.dictation.level.current,
                                    onClose: () =>
                                        setState(() => _open = false),
                                    onExpand: _submit,
                                  ),
                                )
                              : _AssistBubble(
                                  alignment: _bubbleAt,
                                  onTap: () => setState(() => _open = true),
                                  onMoved: (alignment) =>
                                      setState(() => _bubbleAt = alignment),
                                ),
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
class _AssistBubble extends StatelessWidget {
  const _AssistBubble({
    required this.onTap,
    required this.alignment,
    required this.onMoved,
  });

  final VoidCallback onTap;
  final Alignment alignment;

  /// Reports where the bubble was dragged to, snapped to a side.
  final ValueChanged<Alignment> onMoved;

  /// Comfortably above the 48dp minimum tap target — this gets pressed with a
  /// thumb, sometimes gloved.
  static const double _diameter = 56;

  /// Breathing room around the orb for its own glow.
  ///
  /// The shadow is drawn outside the 56px circle, so with the bubble flush
  /// against the edge of its container the halo was sliced off on that side —
  /// which read as a rendering fault rather than as a design. Reserving the
  /// space keeps the glow whole in every resting position.
  static const double _halo = 14;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ask about the register. Drag to move.',
      child: Draggable<Object>(
        feedback: Material(
          color: Colors.transparent,
          child: _orb(context, dragging: true),
        ),
        childWhenDragging: const SizedBox(
          width: _diameter + _halo * 2,
          height: _diameter + _halo * 2,
        ),
        onDragEnd: (details) => onMoved(_snap(context, details.offset)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: _orb(context),
          ),
        ),
      ),
    );
  }

  /// Snaps a drop point to one of six resting places.
  ///
  /// Free positioning sounds friendlier and is worse: a bubble left at an
  /// arbitrary offset drifts under the status bar, half off the edge, or on
  /// top of the navigation bar, and it has to be rescued. Snapping to a side
  /// keeps every resting place a usable one.
  Alignment _snap(BuildContext context, Offset dropped) {
    final size = MediaQuery.sizeOf(context);
    final x = dropped.dx + _diameter / 2 < size.width / 2 ? -1.0 : 1.0;
    final y = switch (dropped.dy + _diameter / 2) {
      final dy when dy < size.height * 0.33 => -1.0,
      final dy when dy < size.height * 0.66 => 0.0,
      _ => 1.0,
    };
    return Alignment(x, y);
  }

  Widget _orb(BuildContext context, {bool dragging = false}) {
    final m = context.metrics;
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.all(_halo),
      child: AiGlowBorder(
      active: true,
      borderRadius: BorderRadius.circular(_diameter / 2),
      strokeWidth: 2,
      child: Container(
        width: _diameter,
        height: _diameter,
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
