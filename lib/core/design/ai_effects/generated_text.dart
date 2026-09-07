import 'package:flutter/material.dart';

import '../../theme/theme_scope.dart';
import 'effects_motion.dart';

/// The hue the generated-text highlighter is washed in: a flat light orange.
///
/// No gradient — a plain marker colour, the way a highlighter pen actually
/// looks. Defined here in the design layer (feature code still may not name a
/// colour). Applied translucently over text that keeps its own colour, so it
/// reads as a mark rather than a fill; see [generatedHighlightColor].
const Color _generatedHighlight = Color(0xFFFFB067);

/// The flat highlighter wash for generated text — light orange, translucent so
/// text stays legible, a touch stronger in the dark theme where a faint wash
/// would vanish. One definition so every surface that marks generated content
/// matches exactly.
Color generatedHighlightColor(BuildContext context) =>
    _generatedHighlight.withValues(alpha: context.isDark ? 0.42 : 0.30);

/// Builds spans for generated text that is streaming in like an assistant
/// writing it — the shared body behind [GeneratedText] and the note review.
///
/// [mask] flags, per character of [full], which characters are the model's (and
/// so carry the highlighter); the rest read plainly. [revealExact] is a
/// *fractional* character count, so the newest glyph fades in over a frame or
/// two rather than snapping — the small thing that makes a typewriter read as
/// smooth instead of steppy. Pass `full.length` to show everything at once. A
/// caret trails the text while it is still being written.
List<InlineSpan> buildGeneratedSpans({
  required BuildContext context,
  required String full,
  required List<bool> mask,
  required double revealExact,
  required Color textColor,
}) {
  final total = full.length;
  final shown = revealExact.ceil().clamp(0, total);
  final typing = shown < total;
  // Characters fully in are everything but the newest, which is fading.
  final headLen = typing ? (shown - 1).clamp(0, total) : shown;
  final highlight = TextStyle(backgroundColor: generatedHighlightColor(context));

  final spans = <InlineSpan>[];
  // Group consecutive same-mark characters into one span rather than one each.
  var i = 0;
  while (i < headLen) {
    final marked = mask[i];
    var j = i + 1;
    while (j < headLen && mask[j] == marked) {
      j++;
    }
    spans.add(TextSpan(
      text: full.substring(i, j),
      style: marked ? highlight : null,
    ));
    i = j;
  }

  if (typing && shown >= 1) {
    final idx = shown - 1;
    final opacity = (revealExact - idx).clamp(0.0, 1.0);
    spans.add(TextSpan(
      text: full.substring(idx, shown),
      style: TextStyle(
        backgroundColor: mask[idx] ? generatedHighlightColor(context) : null,
        color: textColor.withValues(alpha: opacity),
      ),
    ));
  }
  if (typing) {
    spans.add(TextSpan(
      text: '▏',
      style: TextStyle(color: context.palette.accent),
    ));
  }
  return spans;
}

/// Text with the machine's contribution marked word by word.
///
/// The panel badge says *a machine touched this*; this says *which words*. In a
/// record read years later that is the difference between "check the whole
/// paragraph" and "check these four words" — and a reviewer who is told exactly
/// what to look at actually looks.
///
/// Given a [source], every run of [text] whose words do not appear in it is
/// swept with the animated highlighter as *new wording*; words carried over
/// verbatim render plainly, because they are the clinician's own and need no
/// second look. With no [source] the whole string is treated as generated — the
/// honest default when there is nothing it was rewritten *from*.
///
/// The comparison is by word, case-folded, exactly like the echo gate in
/// `note_drafting.dart`: a dose ("500") or a drug name that survives the
/// rewrite is *kept*, not flagged, so the highlight never cries wolf over the
/// numbers a clinician most needs to trust. The mark runs continuously across a
/// phrase — the spaces between two highlighted words are highlighted too — so it
/// reads as one swipe of a pen rather than a row of separate blocks.
///
/// The gradient drifts unless the platform asks for reduced motion, where it
/// freezes to a static sweep rather than merely slowing.
class GeneratedText extends StatefulWidget {
  const GeneratedText({
    super.key,
    required this.text,
    this.source,
    this.style,
    this.typeIn = false,
  });

  /// The text a model produced.
  final String text;

  /// What it was rewritten from. Words shared with it are treated as kept;
  /// null means treat every word as new.
  final String? source;

  final TextStyle? style;

  /// Reveal the text once, character by character with a caret, as though the
  /// model were writing it now. For the first appearance of freshly generated
  /// text — it makes the wait legible ("this was just written") rather than
  /// pretending the paragraph was always there. Off by default; the gradient
  /// highlighter runs either way.
  final bool typeIn;

  /// Matches a word — letters/digits, with internal apostrophes or hyphens so
  /// "patient's" and "twice-daily" stay whole. Everything between matches
  /// (spaces, full stops, commas) is emitted untouched.
  static final RegExp _word =
      RegExp(r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*");

  static String _fold(String word) => word.toLowerCase();

  /// The case-folded words of [value], for membership testing.
  static Set<String> _vocabulary(String value) =>
      _word.allMatches(value).map((m) => _fold(m.group(0)!)).toSet();

  @override
  State<GeneratedText> createState() => _GeneratedTextState();
}

class _GeneratedTextState extends State<GeneratedText>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // The one-time reveal, if [GeneratedText.typeIn]. Paced by length so a line
  // and a paragraph both take a readable — not tedious — moment.
  AnimationController? _typer;
  bool _typingStarted = false;

  /// Which characters of the text are the model's, computed once — the reveal
  /// replays it every frame, but the classification never changes.
  late List<bool> _mask;

  // Once this text can write itself in, keep its state alive for as long as it
  // is in the list. Scrolling it out of view and back must not dispose the
  // state and replay the reveal from zero — the reveal is a one-time "this was
  // just written" gesture, not something to re-run every time it reappears.
  @override
  bool get wantKeepAlive => _typer != null;

  @override
  void initState() {
    super.initState();
    _mask = _computeMask();
    if (widget.typeIn) {
      _typer = AnimationController(
        vsync: this,
        duration: Duration(
          milliseconds: (widget.text.length * 18).clamp(500, 3500),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(GeneratedText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.source != widget.source) {
      _mask = _computeMask();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Started here, not in initState, because whether to animate depends on the
    // reduced-motion query, which needs the inherited MediaQuery.
    final typer = _typer;
    if (typer != null && !_typingStarted) {
      _typingStarted = true;
      if (prefersReducedMotion(context)) {
        typer.value = 1;
      } else {
        typer.forward();
      }
    }
  }

  @override
  void dispose() {
    _typer?.dispose();
    super.dispose();
  }

  /// A per-character flag of what is new wording. A word absent from the source
  /// is marked, and so are the gaps between two marked words, so a phrase reads
  /// as one continuous swipe.
  List<bool> _computeMask() {
    final full = widget.text;
    final mask = List<bool>.filled(full.length, false);
    final source = widget.source;
    final known =
        source == null ? const <String>{} : GeneratedText._vocabulary(source);
    final matches = GeneratedText._word.allMatches(full).toList();
    final isNew = <bool>[
      for (final match in matches)
        source == null ||
            !known.contains(GeneratedText._fold(match.group(0)!)),
    ];
    for (var k = 0; k < matches.length; k++) {
      if (!isNew[k]) continue;
      for (var p = matches[k].start; p < matches[k].end; p++) {
        mask[p] = true;
      }
    }
    for (var k = 0; k + 1 < matches.length; k++) {
      if (isNew[k] && isNew[k + 1]) {
        for (var p = matches[k].end; p < matches[k + 1].start; p++) {
          mask[p] = true;
        }
      }
    }
    return mask;
  }

  Widget _rich(BuildContext context, double reveal) {
    final base =
        (widget.style ?? context.texts.bodyMedium ?? const TextStyle());
    final spans = buildGeneratedSpans(
      context: context,
      full: widget.text,
      mask: _mask,
      revealExact: reveal * widget.text.length,
      textColor: base.color ?? context.palette.onSurface,
    );
    return Text.rich(TextSpan(style: base, children: spans));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    final typer = _typer;
    // Nothing animates once the highlighter is flat and the reveal is off or
    // done — just paint the text.
    if (typer == null) return _rich(context, 1);
    return AnimatedBuilder(
      animation: typer,
      // easeOut so the writing starts brisk and settles, rather than the
      // mechanical constant rate of a linear reveal.
      builder: (context, _) =>
          _rich(context, Curves.easeOut.transform(typer.value)),
    );
  }
}

/// A one-line key for what the tinting in [GeneratedText] means.
///
/// Shown once beside the text, not per word: the mark has to be legible on its
/// own, but the reader only needs telling what it means the first time.
class GeneratedTextLegend extends StatelessWidget {
  const GeneratedTextLegend({
    super.key,
    this.newLabel = 'new wording',
    this.keptLabel = 'kept from your text',
  });

  final String newLabel;
  final String keptLabel;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final label = context.texts.labelSmall?.copyWith(
      color: palette.onSurfaceMuted,
    );

    return Wrap(
      spacing: m.spaceMd,
      runSpacing: m.spaceXs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text.rich(
          TextSpan(
            style: label,
            children: <InlineSpan>[
              // The swatch is the mark itself: the word shown exactly as it
              // appears in the text, highlighter and all.
              TextSpan(
                text: ' $newLabel ',
                style: TextStyle(
                  backgroundColor: generatedHighlightColor(context),
                ),
              ),
              const TextSpan(text: ' — read these'),
            ],
          ),
        ),
        Text('$keptLabel — your own words', style: label),
      ],
    );
  }
}
