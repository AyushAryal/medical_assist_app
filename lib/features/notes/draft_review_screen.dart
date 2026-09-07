import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../core/routing/fade_through_route.dart';
import '../../data/services/assist/note_drafting.dart';
import 'section_proposal.dart';
import 'widgets/draft_proposal_card.dart';
import 'widgets/draft_review_chrome.dart';

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
      FadeThroughRoute<Map<String, String>>(
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
          sentences: widget.draft.provenance[key] ?? const <DraftSentence>[],
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
            DraftPreamble(engineName: widget.draft.engineName),
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
              ProposalCard(
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
      bottomNavigationBar: ApplyBar(
        keeping: _keeping,
        total: _proposals.length,
        onApply: _keeping == 0 ? null : _apply,
        onDiscard: () => Navigator.of(context).pop(),
      ),
    );
  }
}
