import 'package:flutter/material.dart';

import '../../ai/follow_ups.dart';
import '../../ai/presentation.dart';
import '../../ai/provenance.dart';
import '../../ai/provenance_explanation.dart';
import '../../core/design/design.dart';
import 'views/chart_view.dart';
import 'views/clarify_view.dart';
import 'views/dashboard_view.dart';
import 'views/mentions_view.dart';
import 'views/message_view.dart';
import 'views/metric_view.dart';
import 'views/proposal_view.dart';
import 'views/data_table_card.dart';
import 'views/patient_summary_view.dart';
import 'views/view_toggle.dart';

/// Renders whatever the pipeline produced, in this app's own visual language.
///
/// One renderer, used by the bubble and by the full search screen. That is the
/// point of [Presentation] being data: the two surfaces previously each built
/// their own idea of what an answer looks like and drifted apart, so a result
/// could read one way in the bubble and another on the page.
///
/// This file owns three things and nothing else: **dispatch** (the switch over
/// the sealed type — adding an output kind is adding a case here and a view
/// file beside the others), **the heading** every answer carries (headline,
/// generated badge, the explanation control, the view toggle), and **the
/// follow-up strip**. How each kind of answer actually looks lives in
/// `views/`, one file per kind, because a renderer that also draws everything
/// it dispatches to is a page nobody can navigate.
///
/// The widget is stateful for exactly one reason: the person reading an answer
/// may switch it between its honest renderings — chart to table, list to table
/// — and that choice belongs to the answer on screen, not to the app. It
/// resets when a new answer arrives, because a preference expressed about a
/// breakdown of visits says nothing about a recall list.
class AssistPresentationView extends StatefulWidget {
  const AssistPresentationView({
    super.key,
    required this.presentation,
    required this.provenance,
    this.compact = false,
    this.isGenerated = false,
    this.onSuggestion,
    this.onExpand,
    this.showHeadline = true,
    this.title,
    this.followUps = const <FollowUp>[],
    this.onFollowUp,
  });

  final Presentation presentation;
  final Provenance provenance;

  /// Trimmed for the floating panel: fewer rows, tighter type, no chart axis
  /// labels. The *content* is identical — a compact answer is the same answer,
  /// not a lesser one.
  final bool compact;

  /// Whether a model contributed. Only then is the badge shown.
  final bool isGenerated;

  final ValueChanged<String>? onSuggestion;

  /// Opens the full screen. Offered whenever a result is larger than the space
  /// it is being shown in.
  final VoidCallback? onExpand;

  /// The re-cuts worth offering for this particular answer.
  final List<FollowUp> followUps;

  /// Runs a follow-up. Unlike a starter chip, which loads the box for editing,
  /// this asks immediately: a starter is a draft of a question, a follow-up is
  /// a refinement of an answer already on screen, and making someone confirm
  /// "show the list" defeats the point of offering it.
  final ValueChanged<FollowUp>? onFollowUp;

  /// False where the caller already showed the headline — the conversation
  /// panel says it in the assistant's own bubble, and repeating it directly
  /// underneath makes the app look like it is stuttering.
  final bool showHeadline;

  /// A short name seated in the control row when [showHeadline] is false —
  /// a dashboard tile's title. On the same line as the view toggle, because a
  /// left-aligned title over a right-floating toggle read as two stray rows.
  final String? title;

  @override
  State<AssistPresentationView> createState() => _AssistPresentationViewState();
}

class _AssistPresentationViewState extends State<AssistPresentationView> {
  /// The rendering the reader picked, or null for the answer's own default.
  ResultView? _chosen;

  int get _rowLimit => widget.compact ? 3 : 25;

  ResultView get _view {
    final views = widget.presentation.views;
    final chosen = _chosen;
    return chosen != null && views.contains(chosen) ? chosen : views.first;
  }

  @override
  void didUpdateWidget(AssistPresentationView old) {
    super.didUpdateWidget(old);
    // A new answer starts at its own best view. Carrying a toggle across
    // unrelated answers would mean a table preference expressed about one
    // breakdown silently reshapes the next recall list.
    if (old.presentation != widget.presentation) _chosen = null;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _heading(context),
        SizedBox(height: m.spaceSm),
        _body(context),
      ],
    );
    if (widget.followUps.isEmpty || widget.onFollowUp == null) return body;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        body,
        SizedBox(height: m.spaceSm),
        // Left of centre and quiet. These are an offer, not the answer; a row
        // of filled buttons under a count competes with the count.
        Wrap(
          spacing: m.spaceSm,
          runSpacing: m.spaceXs,
          children: <Widget>[
            for (final followUp in widget.followUps)
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  Icons.auto_awesome_outlined,
                  size: 14,
                  color: context.palette.accent,
                ),
                label: Text(followUp.label, style: context.texts.labelSmall),
                onPressed: () => widget.onFollowUp!(followUp),
              ),
          ],
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final presentation = widget.presentation;
    return switch (presentation) {
      MetricPresentation() => MetricAnswerView(
          result: presentation,
          view: _view,
          compact: widget.compact,
          rowLimit: _rowLimit,
          onExpand: widget.onExpand,
        ),
      ChartPresentation() => ChartAnswerView(
          result: presentation,
          view: _view,
          compact: widget.compact,
          rowLimit: _rowLimit,
        ),
      TablePresentation() => AnswerTableCard(
          title: 'Breakdown',
          columns: presentation.columns,
          rows: presentation.rows,
        ),
      MentionsPresentation() => MentionsAnswerView(
          result: presentation,
          compact: widget.compact,
          rowLimit: _rowLimit,
          onExpand: widget.onExpand,
        ),
      ProposalPresentation() => ProposalAnswerView(result: presentation),
      DashboardPresentation() => DashboardAnswerView(
          result: presentation,
          compact: widget.compact,
          // Each tile is rendered exactly the way a lone answer is, minus the
          // headline (the tile title already says what it is). Everything a
          // single answer guarantees — its own explanation, its own honest
          // emptiness — holds per tile because it *is* the same renderer.
          panelBuilder: (title, body) => AssistPresentationView(
            presentation: body,
            provenance: widget.provenance,
            compact: true,
            showHeadline: false,
            title: title,
            isGenerated: false,
          ),
        ),
      ClarifyPresentation() => ClarifyAnswerView(
          result: presentation,
          onPick: widget.onFollowUp == null
              ? null
              : (question) => widget.onFollowUp!(
                    FollowUp(label: question, text: question),
                  ),
        ),
      MessagePresentation() => MessageAnswerView(
          result: presentation,
          onSuggestion: widget.onSuggestion,
        ),
      PatientSummaryPresentation() =>
        PatientSummaryAnswerView(result: presentation),
    };
  }

  /// The header every answer carries: what it says, the way to interrogate how
  /// it got there, and — where more than one rendering is honest — the toggle.
  Widget _heading(BuildContext context) {
    final m = context.metrics;
    final toggle = ViewToggle(
      views: widget.presentation.views,
      current: _view,
      onChanged: (view) => setState(() => _chosen = view),
    );
    final explanation = InfoDot(
      explanation: ProvenanceExplanation.of(
        widget.provenance,
        widget.presentation,
      ),
      semanticLabel: 'How this answer was reached',
    );

    if (!widget.showHeadline) {
      // The explanation control still has to be reachable — an answer that
      // cannot say how it was reached is exactly what this app refuses.
      return Row(
        children: <Widget>[
          Expanded(
            child: widget.title == null
                ? const SizedBox.shrink()
                : Text(
                    widget.title!,
                    style: context.texts.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          SizedBox(width: m.spaceXs),
          toggle,
          SizedBox(width: m.spaceXs),
          if (widget.isGenerated) const AiBadge(dense: true),
          explanation,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            widget.presentation.headline,
            style: widget.compact
                ? context.texts.bodySmall
                : context.texts.bodyLarge,
          ),
        ),
        SizedBox(width: m.spaceXs),
        toggle,
        if (widget.isGenerated) ...<Widget>[
          SizedBox(width: m.spaceXs),
          const AiBadge(dense: true),
        ],
        explanation,
      ],
    );
  }
}
