import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/design.dart';
import '../../data/services/assist/note_drafting.dart';

/// One section's proposal, and what the clinician decided about it.
class SectionProposal {
  SectionProposal({
    required this.key,
    required this.title,
    required this.before,
    required this.proposed,
    this.keep = true,
  });

  final String key;
  final String title;

  /// What is in the field now. Shown above the proposal so the change is
  /// visible as a change, not as a block of text to compare from memory.
  final String before;

  /// What the model suggests adding to this section.
  final String proposed;

  /// Accepted by default — the draft has already passed the word-for-word
  /// gate, and defaulting to discard would make the common case four extra
  /// taps. Every one is still individually refusable.
  bool keep;

  bool get isAddition => before.trim().isNotEmpty;
}

/// Review a model's sorting, section by section, before any of it lands.
///
/// This replaced a sheet that applied all four sections at once and announced
/// it in a snackbar that disappeared. Two things were wrong with that. A
/// clinician could not see *what changed* — only that something had — and
/// they could not disagree with one section without rejecting the sort
/// entirely. Both matter more here than anywhere else in the app, because
/// what is being changed is the record.
///
/// So: every section shows what was there and what would be added, generated
/// text is tinted in the accent (never a severity colour — this is not a
/// clinical judgement), and each section is kept or discarded on its own.
/// Nothing is applied until Apply is pressed, and Apply says how many
/// sections it will touch.
class DraftReviewScreen extends StatefulWidget {
  const DraftReviewScreen({
    super.key,
    required this.draft,
    required this.current,
    required this.source,
  });

  final SoapDraft draft;

  /// The sections as they stand, keyed the same way.
  final Map<String, String> current;

  /// The working notes the sort came from, shown so the clinician can check
  /// the sort against the words they actually said.
  final String source;

  static const Map<String, String> titles = <String, String>{
    'subjective': 'Subjective',
    'objective': 'Objective',
    'assessment': 'Assessment',
    'plan': 'Plan',
  };

  /// Returns the sections to apply, or null if nothing was accepted.
  static Future<Map<String, String>?> show(
    BuildContext context, {
    required SoapDraft draft,
    required Map<String, String> current,
    required String source,
  }) {
    return Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute<Map<String, String>>(
        fullscreenDialog: true,
        builder: (context) => DraftReviewScreen(
          draft: draft,
          current: current,
          source: source,
        ),
      ),
    );
  }

  @override
  State<DraftReviewScreen> createState() => _DraftReviewScreenState();
}

class _DraftReviewScreenState extends State<DraftReviewScreen> {
  late final List<SectionProposal> _proposals = <SectionProposal>[
    for (final key in NoteDrafting.sectionKeys)
      if ((widget.draft.sections[key] ?? '').trim().isNotEmpty)
        SectionProposal(
          key: key,
          title: DraftReviewScreen.titles[key]!,
          before: widget.current[key] ?? '',
          proposed: widget.draft.sections[key]!.trim(),
        ),
  ];

  bool _showSource = false;

  int get _keeping => _proposals.where((p) => p.keep).length;

  void _apply() {
    Navigator.of(context).pop(<String, String>{
      for (final proposal in _proposals)
        if (proposal.keep) proposal.key: proposal.proposed,
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Review the sort'),
        actions: <Widget>[
          IconButton(
            tooltip: _showSource ? 'Hide what you said' : 'Show what you said',
            icon: Icon(
              _showSource ? Icons.notes : Icons.notes_outlined,
            ),
            onPressed: () => setState(() => _showSource = !_showSource),
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: pagePadding(context, floatingBar: true),
          children: <Widget>[
            _Preamble(engineName: widget.draft.engineName),
            SizedBox(height: m.spaceMd),

            if (_showSource) ...<Widget>[
              SectionCard(
                title: 'What you said',
                subtitle: 'The sort must use these words and no others',
                leading: const Icon(Icons.record_voice_over_outlined, size: 20),
                child: Text(
                  widget.source,
                  style: context.texts.bodySmall,
                ),
              ),
              SizedBox(height: m.spaceMd),
            ],

            for (final proposal in _proposals) ...<Widget>[
              _ProposalCard(
                proposal: proposal,
                onChanged: (keep) => setState(() => proposal.keep = keep),
              ),
              SizedBox(height: m.spaceMd),
            ],

            if (widget.draft.unplaced.isNotEmpty) ...<Widget>[
              SectionCard(
                title: 'Staying in your working notes',
                subtitle:
                    '${widget.draft.unplaced.length} sentence'
                        '${widget.draft.unplaced.length == 1 ? '' : 's'} '
                        'nothing could place',
                leading: Icon(
                  Icons.help_outline,
                  size: 20,
                  color: context.palette.onSurfaceMuted,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final sentence in widget.draft.unplaced)
                      Padding(
                        padding: EdgeInsets.only(bottom: m.spaceXs),
                        child: Text(
                          '· $sentence',
                          style: context.texts.bodySmall,
                        ),
                      ),
                    SizedBox(height: m.spaceXs),
                    Text(
                      'These are left where they are rather than guessed at. '
                      'A sentence in the wrong section is worse than one '
                      'still waiting.',
                      style: context.texts.labelSmall?.copyWith(
                        color: context.palette.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: m.spaceMd),
            ],

            if (_proposals.isEmpty)
              const EmptyState(
                icon: Icons.inbox_outlined,
                title: 'Nothing to sort',
                message: 'The model found no sections in that text.',
              ),
          ],
        ),
      ),
      bottomNavigationBar: _ApplyBar(
        keeping: _keeping,
        total: _proposals.length,
        onApply: _keeping == 0 ? null : _apply,
        onDiscard: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// What the reader needs to know before judging any of it.
class _Preamble extends StatelessWidget {
  const _Preamble({required this.engineName});

  final String engineName;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const AiSparkleIcon(size: 20),
        SizedBox(width: m.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'Sorted by $engineName',
                    style: context.texts.labelLarge,
                  ),
                  SizedBox(width: m.spaceXs),
                  const AiBadge(dense: true),
                ],
              ),
              SizedBox(height: m.spaceXs),
              Text(
                'Your sentences, filed — never reworded. Each one below is '
                'exactly what you dictated. Keep the sections you agree with; '
                'nothing changes until you apply.',
                style: context.texts.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One section: what is there, what would be added, keep or discard.
class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.proposal, required this.onChanged});

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
      trailing: Switch(
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
          // The generated text, tinted. The accent and never a severity
          // colour: red in this app means a patient is unwell, and "a machine
          // wrote this" must not borrow that vocabulary.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: kept ? 1 : 0.45,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(m.spaceSm),
              decoration: BoxDecoration(
                color: kept
                    ? palette.accentSubtle
                    : palette.surfaceMuted.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(m.radiusSm),
                border: Border.all(
                  color: kept
                      ? palette.accent.withValues(alpha: 0.45)
                      : palette.outline.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                proposal.proposed,
                style: context.texts.bodyMedium?.copyWith(
                  color: kept ? palette.onSurface : palette.onSurfaceMuted,
                  decoration: kept ? null : TextDecoration.lineThrough,
                ),
              ),
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
              Text(
                kept
                    ? 'Will go into ${proposal.title}'
                    : 'Discarded — ${proposal.title} stays as it is',
                style: context.texts.labelSmall
                    ?.copyWith(color: palette.onSurfaceMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The commit bar: what will happen, in a sentence, before it happens.
class _ApplyBar extends StatelessWidget {
  const _ApplyBar({
    required this.keeping,
    required this.total,
    required this.onApply,
    required this.onDiscard,
  });

  final int keeping;
  final int total;
  final VoidCallback? onApply;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return GlassChrome(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(m.spaceMd),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  keeping == 0
                      ? 'Nothing selected'
                      : 'Keeping $keeping of $total '
                          '${total == 1 ? 'section' : 'sections'}',
                  style: context.texts.labelMedium,
                ),
              ),
              TextButton(
                onPressed: onDiscard,
                child: const Text('Discard all'),
              ),
              SizedBox(width: m.spaceSm),
              FilledButton.icon(
                onPressed: onApply == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onApply!();
                      },
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Apply'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
