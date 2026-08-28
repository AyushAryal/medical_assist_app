import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/core/design/design.dart';
import 'package:medical_app/core/theme/theme_config.dart';

/// The AI effects wrap live, focused input — the assistant's question box sits
/// inside them. That makes one property load-bearing: **they must not change
/// the shape of the tree beneath them when they turn on or off.**
///
/// A widget that returns its child directly when inactive and a wrapper when
/// active moves everything below it to a different depth. Flutter then rebuilds
/// that subtree, a rebuilt `EditableText` loses its connection state, and the
/// platform keyboard re-applies its composing region — which shows up as
/// deleted characters reappearing as the user types.
/// The tokens the effects read. Built from the real JSON parser with an empty
/// map, so every value is the documented default rather than something made up
/// for the test.
final ThemeConfig _config = ThemeConfig.fromJson(<String, dynamic>{
  'id': 'test',
  'name': 'Test',
  'typography': <String, dynamic>{},
  'metrics': <String, dynamic>{},
  'light': <String, dynamic>{},
  'dark': <String, dynamic>{},
});

void main() {
  Widget host({
    required Widget child,
    double bottomInset = 0,
  }) {
    return MediaQuery(
      data: MediaQueryData(
        viewInsets: EdgeInsets.only(bottom: bottomInset),
      ),
      child: ThemeScope(
        config: _config,
        brightness: Brightness.light,
        child: MaterialApp(
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  Element elementOf(WidgetTester tester) =>
      tester.element(find.byType(EditableText));

  group('GeneratedSpanController', () {
    // Pulls the leaf spans out of whatever buildTextSpan produced, so a test
    // can ask which text was styled and which was left plain.
    List<TextSpan> leaves(TextSpan root) {
      final out = <TextSpan>[];
      void walk(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text != null) out.add(span);
          for (final child in span.children ?? const <InlineSpan>[]) {
            walk(child);
          }
        }
      }

      walk(root);
      return out;
    }

    bool isMarked(TextSpan span) =>
        span.style?.background != null || span.style?.backgroundColor != null;

    testWidgets('highlights exactly the generated span', (tester) async {
      final controller = GeneratedSpanController(text: 'Cough for 3 days. '
          'Likely viral.');
      addTearDown(controller.dispose);
      await tester.pumpWidget(host(child: TextField(controller: controller)));

      // "Likely viral." is what the model placed; the rest is the clinician's.
      controller.markGenerated(
        snapshot: controller.text,
        range: const TextRange(start: 18, end: 31),
      );

      final span = controller.buildTextSpan(
        context: elementOf(tester),
        style: const TextStyle(),
        withComposing: false,
      );
      final marked = leaves(span).where(isMarked).map((s) => s.text).join();
      expect(marked, 'Likely viral.');
    });

    testWidgets('the highlight falls away on the first edit', (tester) async {
      final controller = GeneratedSpanController(text: 'Likely viral.');
      addTearDown(controller.dispose);
      await tester.pumpWidget(host(child: TextField(controller: controller)));
      controller.markGenerated(
        snapshot: controller.text,
        range: const TextRange(start: 0, end: 13),
      );

      // A clinician types — the snapshot no longer matches.
      controller.text = 'Likely viral URI.';

      final span = controller.buildTextSpan(
        context: elementOf(tester),
        style: const TextStyle(),
        withComposing: false,
      );
      expect(leaves(span).any(isMarked), isFalse);
    });

    testWidgets('clearGenerated removes the mark', (tester) async {
      final controller = GeneratedSpanController(text: 'Likely viral.');
      addTearDown(controller.dispose);
      await tester.pumpWidget(host(child: TextField(controller: controller)));
      controller.markGenerated(
        snapshot: controller.text,
        range: const TextRange(start: 0, end: 13),
      );
      controller.clearGenerated();

      final span = controller.buildTextSpan(
        context: elementOf(tester),
        style: const TextStyle(),
        withComposing: false,
      );
      expect(leaves(span).any(isMarked), isFalse);
    });
  });

  group('GeneratedText typewriter', () {
    // Scoped to the GeneratedText so a stray RichText elsewhere can't confuse
    // the finder; the caret glyph is stripped so we compare only real text.
    String shown(WidgetTester tester) {
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byType(GeneratedText),
          matching: find.byType(RichText),
        ),
      );
      return (rich.text as TextSpan).toPlainText().replaceAll('▏', '');
    }

    testWidgets('reveals the text over time, then shows all of it',
        (tester) async {
      const full = 'Take paracetamol when you have a fever.';
      await tester.pumpWidget(host(
        child: const GeneratedText(text: full, typeIn: true),
      ));
      await tester.pump(); // start the reveal

      // Part-way through, only a prefix is on screen.
      await tester.pump(const Duration(milliseconds: 150));
      final midway = shown(tester);
      expect(full.startsWith(midway), isTrue);
      expect(midway.length, lessThan(full.length));

      // Past the reveal duration the whole text is there. Not pumpAndSettle:
      // the highlighter sweep loops forever and would never settle.
      await tester.pump(const Duration(seconds: 2));
      expect(shown(tester), full);
    });

    testWidgets('with reduced motion the whole text is shown at once',
        (tester) async {
      const full = 'Come back in one week.';
      // The MediaQuery must sit *below* MaterialApp to be the nearest one the
      // widget reads, so it is passed as the child rather than wrapping host.
      await tester.pumpWidget(host(
        child: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: GeneratedText(text: full, typeIn: true),
        ),
      ));
      await tester.pump();
      expect(shown(tester), full);
    });
  });

  group('AiGlowBorder', () {
    testWidgets('keeps the subtree in place when it activates', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      Widget build(bool active) => host(
            child: AiGlowBorder(
              active: active,
              child: TextField(controller: controller),
            ),
          );

      await tester.pumpWidget(build(false));
      final before = elementOf(tester);

      await tester.pumpWidget(build(true));
      final after = elementOf(tester);

      expect(
        identical(before, after),
        isTrue,
        reason: 'activating the border must not rebuild the field beneath it',
      );
    });

    testWidgets('text survives activation and deactivation', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      Widget build(bool active) => host(
            child: AiGlowBorder(
              active: active,
              child: TextField(controller: controller),
            ),
          );

      await tester.pumpWidget(build(false));
      await tester.enterText(find.byType(TextField), 'warfarin');

      await tester.pumpWidget(build(true));
      await tester.pump();
      expect(controller.text, 'warfarin');

      await tester.pumpWidget(build(false));
      await tester.pump();
      expect(controller.text, 'warfarin');
    });

    testWidgets('deleting characters actually deletes them', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        host(
          child: AiGlowBorder(
            active: true,
            child: TextField(controller: controller),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'warfarin');
      await tester.pump();
      // What a backspace amounts to from the framework's side.
      await tester.enterText(find.byType(TextField), 'warfari');
      await tester.pump();

      expect(controller.text, 'warfari');
    });
  });

  group('AiAuroraBackground', () {
    testWidgets('keeps the subtree in place when it activates', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      Widget build(bool active) => host(
            child: AiAuroraBackground(
              active: active,
              child: TextField(controller: controller),
            ),
          );

      await tester.pumpWidget(build(false));
      final before = elementOf(tester);

      await tester.pumpWidget(build(true));
      expect(identical(before, elementOf(tester)), isTrue);
    });
  });

  group('animation regressions', _animationRegressions);

  group('a repositioning parent', () {
    testWidgets('moving with the keyboard does not rebuild the field',
        (tester) async {
      // The assistant is anchored above the keyboard, so its position changes
      // on every frame of the keyboard animation. That must reposition the
      // panel without disturbing what is being typed into it.
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      Widget build(double inset) => host(
            bottomInset: inset,
            child: Stack(
              children: <Widget>[
                const SizedBox.expand(),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: inset > 0 ? inset + 12 : 96,
                  child: AiGlowBorder(
                    active: false,
                    child: TextField(controller: controller),
                  ),
                ),
              ],
            ),
          );

      await tester.pumpWidget(build(0));
      await tester.enterText(find.byType(TextField), 'appointments');
      final before = elementOf(tester);

      for (final inset in <double>[40, 120, 280]) {
        await tester.pumpWidget(build(inset));
        await tester.pump();
      }

      expect(identical(before, elementOf(tester)), isTrue);
      expect(controller.text, 'appointments');
    });
  });
}

/// Regression cover for effects that looked animated in code and sat frozen on
/// screen.
///
/// The cause each time was the same shape of mistake: reading the controller's
/// value in `build` and closing over it, so `AnimatedBuilder` re-ran a closure
/// that held a value from whenever the *parent* last rebuilt. On a badge
/// sitting in a static panel, that is never.
void _animationRegressions() {
  final ThemeConfig config = ThemeConfig.fromJson(<String, dynamic>{
    'id': 'test',
    'name': 'Test',
    'typography': <String, dynamic>{},
    'metrics': <String, dynamic>{},
    'light': <String, dynamic>{},
    'dark': <String, dynamic>{},
  });

  Widget host(Widget child) => ThemeScope(
        config: config,
        brightness: Brightness.light,
        child: MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  /// The gradient actually painted on the badge this frame.
  Gradient? gradientOf(WidgetTester tester) {
    final container = tester.widgetList<Container>(find.byType(Container));
    for (final widget in container) {
      final decoration = widget.decoration;
      if (decoration is BoxDecoration && decoration.gradient != null) {
        return decoration.gradient;
      }
    }
    return null;
  }

  testWidgets('AiBadge keeps moving between frames', (tester) async {
    await tester.pumpWidget(host(const AiBadge(label: 'AI generated')));
    await tester.pump();

    final first = gradientOf(tester);
    expect(first, isNotNull, reason: 'the badge paints a gradient');

    await tester.pump(const Duration(milliseconds: 700));
    final second = gradientOf(tester);

    expect(
      second,
      isNot(equals(first)),
      reason: 'a badge that paints the same gradient every frame is frozen',
    );
  });

  testWidgets('AiBadge holds still when motion is reduced', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: host(const AiBadge(label: 'AI generated')),
      ),
    );
    await tester.pump();

    final first = gradientOf(tester);
    await tester.pump(const Duration(milliseconds: 700));

    expect(gradientOf(tester), equals(first));
  });
}
