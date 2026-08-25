import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/ai/cohort/assist_reply.dart';
import 'package:medical_app/core/theme/theme_config.dart';
import 'package:medical_app/core/design/design.dart';
import 'package:medical_app/ai/pipeline.dart';
import 'package:medical_app/ai/presentation.dart';
import 'package:medical_app/ai/provenance.dart';
import 'package:medical_app/ai/assist_request.dart';
import 'package:medical_app/ai/intent.dart';
import 'package:medical_app/features/assist/assistant_panel.dart';

/// The text field in this panel was reported broken three times, and each
/// earlier fix was a guess because there was no way to reproduce it below the
/// level of a running phone. These tests reproduce it.
///
/// The failure: on Android the platform keyboard keeps its own copy of what is
/// being typed, and re-sends that copy whenever the input connection is
/// re-established. Clearing a `TextEditingController` only changes Flutter's
/// side of the story — so the question just asked reappeared over the next one,
/// and characters deleted before a reconnection came back with them.
final ThemeConfig _config = ThemeConfig.fromJson(<String, dynamic>{
  'id': 'test',
  'name': 'Test',
  'typography': <String, dynamic>{},
  'metrics': <String, dynamic>{},
  'light': <String, dynamic>{},
  'dark': <String, dynamic>{},
});

void main() {
  /// `pumpAndSettle` never returns here: the header sparkle and the glow
  /// border repeat indefinitely by design, so the scheduler is never idle.
  /// Pumping a bounded number of frames is the correct tool for a screen that
  /// is legitimately always animating.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    // Long enough for the transcript's scroll-to-end to finish. Tapping a
    // target that is still sliding is how a test misses a button that a person
    // would hit.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 40));
  }

  Widget host(Widget child) => ThemeScope(
        config: _config,
        brightness: Brightness.light,
        child: MaterialApp(home: Scaffold(body: child)),
      );

  /// A canned pipeline result, so the panel can be driven without a database.
  AssistResult answerFor(String question) => AssistResult(
        request: AssistRequest(text: question, source: RequestSource.typed),
        intent: const UnknownIntent(reason: 'test'),
        presentation: MessagePresentation(
          headline: 'I found 3 for "$question".',
        ),
        provenance: Provenance(),
      );

  Widget panel({
    Future<AssistResult> Function(String)? onAsk,
    List<String>? asked,
  }) {
    final log = asked ?? <String>[];
    return AssistantPanel(
      guide: const MetricExplanation(
        title: 'What the search understands',
        summary: 'Name a table to search it.',
      ),
      greeting: const AssistReply(
        text: 'Ask me about the register.',
        // Deliberately not a phrase any test then types, so a chip and a
        // question bubble can never be confused for one another.
        suggestions: <String>['suggested starting point'],
      ),
      onAsk: onAsk ??
          (question) async {
            log.add(question);
            return answerFor(question);
          },
      onClose: () {},
      onExpand: (_) {},
    );
  }

  TextEditingController controllerOf(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!;

  group('the input box', () {
    testWidgets('deleting characters deletes them', (tester) async {
      await tester.pumpWidget(host(panel()));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'warfarin');
      await tester.enterText(find.byType(TextField), 'warfari');
      await tester.pump();

      expect(controllerOf(tester).text, 'warfari');
    });

    testWidgets('a submitted question does not survive into the next one',
        (tester) async {
      final asked = <String>[];
      await tester.pumpWidget(host(panel(asked: asked)));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'everyone on warfarin');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      expect(asked, <String>['everyone on warfarin']);
      expect(
        controllerOf(tester).text,
        isEmpty,
        reason: 'the box must be empty and ready for the next question',
      );
    });

    testWidgets('a replay arriving much later is still caught', (tester) async {
      // The replay does not arrive on a schedule. It arrives when the input
      // connection is next established — usually when the field is tapped
      // again, which can be a minute later. A timed guard misses that
      // entirely, which is why the guard is now released by the person typing
      // rather than by a clock.
      await tester.pumpWidget(host(panel()));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'everyone on warfarin');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      await tester.pump(const Duration(seconds: 30));

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'everyone on warfarin',
          selection: TextSelection.collapsed(offset: 20),
        ),
      );
      await tester.pump();

      expect(controllerOf(tester).text, isEmpty);
    });

    testWidgets('asking the same question again by hand still works',
        (tester) async {
      // The guard must not eat a deliberate repeat. Typing produces a first
      // character that differs from the guarded text, which releases it.
      final asked = <String>[];
      await tester.pumpWidget(host(panel(asked: asked)));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'everyone on warfarin');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      // Character by character, as a person types.
      for (var i = 1; i <= 'everyone on warfarin'.length; i++) {
        await tester.enterText(
          find.byType(TextField),
          'everyone on warfarin'.substring(0, i),
        );
      }
      await settle(tester);

      expect(controllerOf(tester).text, 'everyone on warfarin');
    });

    testWidgets('a stale value from the keyboard cannot resurrect a question',
        (tester) async {
      // The reported bug, reproduced. After a question is submitted the
      // platform keyboard re-sends the buffer it still holds. If that reaches
      // the same input connection, the old question reappears — mixed into
      // whatever is being typed next.
      await tester.pumpWidget(host(panel()));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'everyone on warfarin');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      // The keyboard, still holding the old text, reports it back.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'everyone on warfarin',
          selection: TextSelection.collapsed(offset: 20),
        ),
      );
      await tester.pump();

      expect(
        controllerOf(tester).text,
        isEmpty,
        reason: 'the connection that held that text was retired on submit',
      );
    });

    testWidgets('the field is rebuilt fresh after each question',
        (tester) async {
      // The mechanism behind the guarantee above: a new key retires the old
      // platform connection outright, which is the only way to be certain the
      // keyboard cannot replay into it.
      await tester.pumpWidget(host(panel()));
      await settle(tester);

      final before = tester.widget<TextField>(find.byType(TextField)).key;

      await tester.enterText(find.byType(TextField), 'appointments this month');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      final after = tester.widget<TextField>(find.byType(TextField)).key;
      expect(after, isNot(before));
    });

    testWidgets('autocorrect and suggestions are off', (tester) async {
      // A query box is full of drug names and surnames — the words a phone
      // keyboard is most confident about "correcting".
      await tester.pumpWidget(host(panel()));
      await settle(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    });

    testWidgets('typing a second question works normally', (tester) async {
      final asked = <String>[];
      await tester.pumpWidget(host(panel(asked: asked)));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'everyone on warfarin');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'appointments this month');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      expect(asked, <String>[
        'everyone on warfarin',
        'appointments this month',
      ]);
    });
  });

  group('the conversation', () {
    testWidgets('shows the greeting, then both sides of each exchange',
        (tester) async {
      await tester.pumpWidget(host(panel()));
      await settle(tester);

      expect(find.text('Ask me about the register.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'everyone on warfarin');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      expect(find.text('everyone on warfarin'), findsOneWidget);
      expect(
        find.text('I found 3 for "everyone on warfarin".'),
        findsOneWidget,
      );
    });

    testWidgets('a suggestion loads into the box instead of running',
        (tester) async {
      final asked = <String>[];
      await tester.pumpWidget(host(panel(asked: asked)));
      await settle(tester);

      await tester.tap(find.text('suggested starting point'));
      await settle(tester);

      // A suggested prompt is a starting point, not a command.
      expect(controllerOf(tester).text, 'suggested starting point');
      expect(asked, isEmpty);
    });

    testWidgets('an empty question is ignored', (tester) async {
      final asked = <String>[];
      await tester.pumpWidget(host(panel(asked: asked)));
      await settle(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      expect(asked, isEmpty);
    });

    testWidgets('the voice control stays visible but disabled when there is '
        'no speech model', (tester) async {
      // It used to vanish, which left "where did dictation go?" with no answer
      // on screen. A disabled control with a tooltip says what to do about it.
      await tester.pumpWidget(host(panel()));
      await settle(tester);

      final mic = find.byIcon(Icons.mic_none_outlined);
      expect(mic, findsOneWidget);
      expect(
        tester.widget<IconButton>(
          find.ancestor(of: mic, matching: find.byType(IconButton)),
        ).onPressed,
        isNull,
      );
    });

    testWidgets('the guide is reachable from the header', (tester) async {
      // It was lost when this panel was extracted into its own widget, which
      // is exactly the kind of thing an extraction loses quietly.
      await tester.pumpWidget(host(panel()));
      await settle(tester);

      expect(find.byType(InfoDot), findsWidgets);
    });

    testWidgets('a question already asked can be reloaded and edited',
        (tester) async {
      final asked = <String>[];
      await tester.pumpWidget(host(panel(asked: asked)));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'everyone on warfarin');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      // The bubble itself is the target — see the note in the panel about why
      // a separate button per question does not survive a capped panel height.
      // The transcript can be taller than the panel now that answers render
      // beneath each reply, so scroll the bubble into view before tapping it.
      await tester.ensureVisible(find.text('everyone on warfarin').first);
      await settle(tester);
      await tester.tap(find.text('everyone on warfarin').first);
      await settle(tester);

      // Refining the last attempt is how anyone uses a search like this.
      expect(controllerOf(tester).text, 'everyone on warfarin');
      expect(asked, hasLength(1), reason: 'editing must not re-run it');
    });

    testWidgets('the clear control appears only when there is text',
        (tester) async {
      await tester.pumpWidget(host(panel()));
      await settle(tester);

      // By tooltip, not by icon: the header's close button is also a cross.
      final clear = find.byTooltip('Clear');
      expect(clear, findsNothing);

      await tester.enterText(find.byType(TextField), 'warfarin');
      await settle(tester);
      expect(clear, findsOneWidget);

      await tester.tap(clear);
      await settle(tester);
      expect(controllerOf(tester).text, isEmpty);
    });

    testWidgets('dictation happens inside the panel, not over it',
        (tester) async {
      await tester.pumpWidget(
        host(
          AssistantPanel(
            guide: const MetricExplanation(title: 'g', summary: 's'),
            greeting: const AssistReply(text: 'hello'),
            onAsk: (question) async => answerFor(question),
            onClose: () {},
            onExpand: (_) {},
            onSpeak: () {},
            isListening: true,
            level: 0.4,
          ),
        ),
      );
      await settle(tester);

      // A modal that covers the conversation you are dictating into is a
      // strange place to put a microphone.
      expect(find.byType(SiriWaveform), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
