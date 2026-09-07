import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../section_proposal.dart';

/// One section: what is there, what would be added, keep or discard.
class ProposalCard extends StatelessWidget {
  const ProposalCard({
    super.key,
    required this.proposal,
    required this.onChanged,
  });

  final SectionProposal proposal;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final kept = proposal.keep;

    return SectionCard(
      title: proposal.title,
      subtitle: proposal.isAddition
          ? 'Would be added below what is already there'
          : 'This section is empty',
      leading: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kept ? palette.accentSubtle : palette.surfaceMuted,
          borderRadius: BorderRadius.circular(m.radiusSm - 2),
        ),
        child: Text(
          proposal.title[0],
          style: context.texts.labelLarge?.copyWith(
            color: kept ? palette.accent : palette.onSurfaceMuted,
          ),
        ),
      ),
      trailing: Switch.adaptive(
        value: kept,
        onChanged: onChanged,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (proposal.isAddition) ...<Widget>[
            Text(
              'Already there',
              style: context.texts.labelSmall
                  ?.copyWith(color: palette.onSurfaceMuted),
            ),
            SizedBox(height: m.spaceXs),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(m.spaceSm),
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(m.radiusSm),
              ),
              child: Text(
                proposal.before.trim(),
                style: context.texts.bodySmall,
              ),
            ),
            SizedBox(height: m.spaceSm),
            Text(
              'Would add',
              style: context.texts.labelSmall
                  ?.copyWith(color: palette.onSurfaceMuted),
            ),
            SizedBox(height: m.spaceXs),
          ],
          // Your words, filed. Nothing here is reworded, so the whole block is
          // *not* tinted as generated — that would misname the clinician's own
          // sentences. Only the sentences the model *placed* are marked, in the
          // accent and never a severity colour: red in this app means a patient
          // is unwell, and "a machine decided this" must not borrow that.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: kept ? 1 : 0.45,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(m.spaceSm),
              decoration: BoxDecoration(
                color: palette.surfaceMuted.withValues(alpha: kept ? 1 : 0.6),
                borderRadius: BorderRadius.circular(m.radiusSm),
                border: Border.all(
                  color: proposal.hasModelPlaced && kept
                      ? palette.accent.withValues(alpha: 0.45)
                      : palette.outline.withValues(alpha: 0.4),
                ),
              ),
              child: ProposedText(proposal: proposal, kept: kept),
            ),
          ),
          SizedBox(height: m.spaceXs),
          Row(
            children: <Widget>[
              Icon(
                kept ? Icons.check_circle_outline : Icons.block,
                size: 13,
                color: kept ? palette.accent : palette.onSurfaceMuted,
              ),
              SizedBox(width: m.spaceXs),
              Expanded(
                child: Text(
                  kept
                      ? proposal.hasModelPlaced
                          ? 'Will go into ${proposal.title} — highlighted '
                              'sentences were filed here by the model, not the '
                              'rules. Check those against what you said.'
                          : 'Will go into ${proposal.title} — every sentence '
                              'filed by the rules.'
                      : 'Discarded — ${proposal.title} stays as it is',
                  style: context.texts.labelSmall
                      ?.copyWith(color: palette.onSurfaceMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The proposed section text, with the model's placements highlighted.
///
/// The rules place most sentences and place them by an explicit clinical cue,
/// so those read plainly — they are as trustworthy as the clinician's own
/// filing. The model places only what the rules could not read, by choosing a
/// section rather than by any rule the screen can show, so those are the ones
/// worth a second look and the only ones marked.
class ProposedText extends StatefulWidget {
  const ProposedText({super.key, required this.proposal, required this.kept});

  final SectionProposal proposal;
  final bool kept;

  @override
  State<ProposedText> createState() => _ProposedTextState();
}

class _ProposedTextState extends State<ProposedText>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // The one-time reveal that streams the section in like an assistant writing.
  AnimationController? _typer;
  bool _typingStarted = false;

  /// The section as one string, and a per-character mask of what the model
  /// placed (and so gets the highlighter). Built once — the sort does not
  /// change under the screen.
  late final String _full;
  late final List<bool> _mask;

  // Keep the card's state alive for as long as it is in the list, so scrolling
  // it off screen and back does not replay the reveal from zero. See the note
  // on the same getter in GeneratedText.
  @override
  bool get wantKeepAlive => _typer != null;

  @override
  void initState() {
    super.initState();
    final sb = StringBuffer();
    final mask = <bool>[];
    final sentences = widget.proposal.sentences;
    for (var i = 0; i < sentences.length; i++) {
      if (i > 0) {
        sb.write(' ');
        mask.add(false);
      }
      final marked = sentences[i].placedByModel;
      sb.write(sentences[i].text);
      mask.addAll(List<bool>.filled(sentences[i].text.length, marked));
    }
    _full = sb.toString();
    _mask = mask;

    if (_full.isNotEmpty) {
      _typer = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: (_full.length * 14).clamp(500, 3500)),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final typer = _typer;
    if (typer != null && !_typingStarted) {
      _typingStarted = true;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
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

  Widget _rich(BuildContext context, double reveal) {
    final palette = context.palette;
    final kept = widget.kept;
    final base = context.texts.bodyMedium?.copyWith(
          color: kept ? palette.onSurface : palette.onSurfaceMuted,
          decoration: kept ? null : TextDecoration.lineThrough,
        ) ??
        const TextStyle();

    // No provenance (e.g. an older draft) — render the plain string.
    if (widget.proposal.sentences.isEmpty) {
      return Text(widget.proposal.proposed, style: base);
    }

    // Discarded sections keep their words but drop the highlighter — nothing is
    // going into the record, so there is nothing to flag.
    final mask = kept ? _mask : List<bool>.filled(_full.length, false);
    return Text.rich(
      TextSpan(
        style: base,
        children: buildGeneratedSpans(
          context: context,
          full: _full,
          mask: mask,
          revealExact: reveal * _full.length,
          textColor: kept ? palette.onSurface : palette.onSurfaceMuted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    final typer = _typer;
    if (typer == null || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return _rich(context, 1);
    }
    return AnimatedBuilder(
      animation: typer,
      builder: (context, _) => _rich(context, Curves.easeOut.transform(typer.value)),
    );
  }
}
