import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the app on one visual language.
///
/// The failure mode this prevents is gradual: a screen needs a slightly
/// different card, someone writes a one-off `BoxDecoration`, and six months
/// later there are nine card styles and no way to restyle the app. Feature
/// code therefore consumes `core/design/design.dart` and never reaches for raw
/// colours, raw radii, or its own surface containers.
///
/// If a screen genuinely needs something new, the fix is to add it to the
/// design layer — not to add an exemption here.
void main() {
  late final List<({String path, String source})> featureFiles;

  setUpAll(() {
    featureFiles = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => (path: f.path, source: f.readAsStringSync()))
        .toList();
  });

  /// Structural uses of Colors.* that carry no brand meaning.
  const allowedColorLiterals = <String>{
    'Colors.transparent',
    'Colors.black', // full-screen image viewer chrome, intentionally absolute
    'Colors.white',
    'Colors.white70',
    'Colors.white54',
  };

  List<String> scan(
    RegExp pattern, {
    bool Function(String line)? ignore,
  }) {
    final hits = <String>[];
    for (final file in featureFiles) {
      final lines = file.source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (ignore != null && ignore(line)) continue;
        if (pattern.hasMatch(line)) {
          hits.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    return hits;
  }

  test('no hardcoded colour literals in feature code', () {
    final hits = scan(
      RegExp(r'\bColors\.[a-zA-Z]+|\bColor\(0x'),
      ignore: (line) =>
          allowedColorLiterals.any(line.contains) &&
          !RegExp(r'Color\(0x').hasMatch(line),
    );

    expect(
      hits,
      isEmpty,
      reason: 'Colours must come from context.palette, not literals.\n'
          '${hits.join('\n')}',
    );
  });

  test('no hardcoded corner radii in feature code', () {
    final hits = scan(RegExp(r'BorderRadius\.circular\(\s*\d'));
    expect(
      hits,
      isEmpty,
      reason: 'Use context.metrics.radiusSm/Md/Lg, not a literal radius.\n'
          '${hits.join('\n')}',
    );
  });

  test('feature code does not define its own card surfaces', () {
    // A raw Card in a feature bypasses the glass surface every panel uses.
    //
    // The pattern was previously anchored to the start of the line, which
    // matched `child: Card(` but sailed straight past `return Card(` — and a
    // one-off Card had in fact reached the patient list that way. Matching the
    // constructor wherever it appears is what actually enforces the rule.
    final hits = scan(RegExp(r'(?<![A-Za-z0-9_])Card\s*\('));
    expect(
      hits,
      isEmpty,
      reason: 'Use SectionCard or GlassPanel from core/design, not Card.\n'
          '${hits.join('\n')}',
    );
  });

  test('feature code does not build its own avatar circles', () {
    // PatientAvatar gives every person a stable per-record colour. A bare
    // CircleAvatar next to it means the same patient is two different colours
    // on two screens, which is exactly the cue people navigate a list by.
    final hits = scan(RegExp(r'(?<![A-Za-z0-9_])CircleAvatar\s*\('));
    expect(
      hits,
      isEmpty,
      reason: 'Use PatientAvatar from core/design, not CircleAvatar.\n'
          '${hits.join('\n')}',
    );
  });

  test('feature code does not build its own gradients', () {
    // The system uses gradients for exactly two things: the ambient background
    // wash, and the AI motion components. Both live in core/design. A gradient
    // written in a screen is decoration, and it is also how the one signal that
    // marks generated content stops being a signal.
    final hits = scan(RegExp(r'(?<![A-Za-z0-9_])(Linear|Radial|Sweep)Gradient'));
    expect(
      hits,
      isEmpty,
      reason: 'Gradients belong in core/design — use AiGlowBorder or '
          'AiShimmer for generated content.\n${hits.join('\n')}',
    );
  });

  test('feature code asks for breakpoints, not for device classes', () {
    // `isTablet` answers the wrong question: a phone in landscape, a small
    // tablet in portrait and a split-screen window all want different layouts
    // and all answer the same way. `context.breakpoint` names the thing that
    // actually decides the layout, which is available width.
    final hits = scan(RegExp(r'context\.isTablet\b'));
    expect(
      hits,
      isEmpty,
      reason: 'Use context.breakpoint (Breakpoint.compact/medium/expanded) '
          'rather than context.isTablet.\n${hits.join('\n')}',
    );
  });

  test('feature code imports the design barrel, not individual widgets', () {
    // Reaching past the barrel is how a second visual language creeps in: it
    // lets a screen depend on an internal that the system does not consider
    // part of its public surface.
    final hits = scan(
      RegExp(r"import '[^']*core/(widgets|theme)/[^']*\.dart'"),
      // ThemeController is application *state* (the light/dark preference),
      // not a visual primitive, so Settings owns it directly. The rule is
      // about components and tokens, not about every file under core/theme.
      ignore: (line) =>
          line.contains('core/design/') ||
          line.contains('theme_controller.dart'),
    );
    expect(
      hits,
      isEmpty,
      reason: "Import 'core/design/design.dart' instead of reaching into "
          'core/widgets or core/theme directly.\n${hits.join('\n')}',
    );
  });

  test('the design barrel exposes the primitives screens rely on', () {
    // Resolve across the barrel plus everything it re-exports, so a symbol
    // living in layout.dart or patterns.dart still counts as exported.
    final barrel = File('lib/core/design/design.dart').readAsStringSync();
    final exported = RegExp(r"export '([^']+)'")
        .allMatches(barrel)
        .map((m) => m.group(1)!)
        .map((rel) => File('lib/core/design/$rel').existsSync()
            ? 'lib/core/design/$rel'
            : 'lib/core/${rel.replaceFirst('../', '')}')
        .where((path) => File(path).existsSync())
        .map((path) => File(path).readAsStringSync())
        .join('\n');
    final surface = '$barrel\n$exported';

    for (final symbol in <String>[
      'GlassPanel',
      'SectionCard',
      'ContentWidth',
      'StatusPill',
      'EmptyState',
      'PatientAvatar',
      'QuickAction',
      'VitalValue',
      'Sparkline',
      'PersonRow',
      'DetailRow',
      'MetricChip',
      'Callout',
      'HeroPanel',
      // Responsive layout: screens must not hand-roll a master–detail split.
      'TwoPane',
      'SplitColumns',
      'AdaptiveColumns',
      'DetailPanePlaceholder',
      // Anything the app worked out for itself has to be able to explain
      // itself. See `clinical/explanations.dart`.
      'InfoDot',
      'ExplainSheet',
      // Motion for generated content — a bounded exception to the
      // minimal-gradients rule, confined to these components on purpose.
      'AiGlowBorder',
      'AiShimmer',
      'AiTextPlaceholder',
      'AiBadge',
      'AiSparkleIcon',
      'AiAuroraBackground',
      'SiriWaveform',
      'PlaybackWaveform',
    ]) {
      expect(
        surface.contains('class $symbol') || barrel.contains(symbol),
        isTrue,
        reason: '\$symbol is not reachable through the design barrel.',
      );
    }
  });

  test('the design concept is documented', () {
    final doc = File('DesignSystem.md');
    expect(
      doc.existsSync(),
      isTrue,
      reason: 'DesignSystem.md records the committed concept; without it the '
          'rules here are unexplained.',
    );
    expect(doc.readAsStringSync().length, greaterThan(500));
  });
}
