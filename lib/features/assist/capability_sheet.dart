import 'package:flutter/material.dart';

import '../../ai/analytics/analysis_examples.dart';
import '../../ai/schema/field_registry.dart';
import '../../ai/cohort/query_vocabulary.dart';
import '../../core/design/design.dart';
import '../../core/utils/formatters.dart';

/// What the assistant can be asked, behind a button.
///
/// This used to live permanently at the top of the Ask page, and permanently is
/// exactly wrong for it. A guide is scaffolding for a first question: worth
/// reading once, and after that it is a third of the screen spent telling
/// someone what they already know. Worse, sitting in the same cards as the
/// answers, it was indistinguishable from them — the page looked like it was
/// always showing results.
///
/// So it comes out on request and goes away again. Everything in it is a
/// button, because a tap is better input than a remembered phrase: it hands
/// the interpreter an unambiguous question instead of leaving it to infer one
/// from whatever the person half-remembered.
///
/// Nothing here is hand-written prose about what *might* work. The clinical
/// starters come from [QueryVocabulary], the chart questions are generated
/// from [FieldRegistry], and tests walk every one of them through the parser —
/// so this sheet cannot advertise a question the app does not answer.
class CapabilitySheet extends StatelessWidget {
  const CapabilitySheet({super.key});

  /// Returns the question that was tapped, or null if the sheet was dismissed.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Tall, because this is a browse-and-choose surface rather than a
      // confirmation. A short sheet that has to be dragged before anything is
      // visible reads as an error.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      builder: (context) => const CapabilitySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return DefaultTabController(
      length: 3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceSm),
            child: Row(
              children: <Widget>[
                const AiSparkleIcon(size: 20),
                SizedBox(width: m.spaceSm),
                Expanded(
                  child: Text(
                    'What you can ask',
                    style: context.texts.titleMedium,
                  ),
                ),
                InfoDot(
                  explanation: QueryVocabulary.schemaReference(),
                  semanticLabel: 'The full list of searchable fields',
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceSm),
            child: Callout(
              title: 'Type \\ for smart phrases',
              icon: Icons.bolt_outlined,
              tone: context.palette.accent,
              subtitle: 'Point at one patient with \\pat — then ask "how is '
                  'this patient progressing" or "summary" and the assistant '
                  'knows exactly who. Also \\me, \\today, \\clinic, and your '
                  'own saved phrases (\\ros, \\normal). Manage them in '
                  'Settings › Smart phrases.',
              child: const SizedBox.shrink(),
            ),
          ),
          const TabBar(
            tabAlignment: TabAlignment.center,
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Clinical'),
              Tab(text: 'Charts'),
              Tab(text: 'Fields'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _ClinicalTab(),
                _ChartsTab(),
                _FieldsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The things a clinician needs a list for.
///
/// Grouped by purpose rather than by table, because "safety" is why someone
/// opens this and "the medications table" is not. Each group says what it is
/// for; a list of example syntax teaches neither.
class _ClinicalTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return ListView(
      padding: EdgeInsets.all(m.spaceLg),
      children: <Widget>[
        for (final group in QueryVocabulary.starters)
          Padding(
            padding: EdgeInsets.only(bottom: m.spaceMd),
            child: SectionCard(
              title: group.title,
              subtitle: group.reason,
              leading: Icon(_icon(group.icon), size: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final starter in group.starters)
                    _QuestionRow(question: starter),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static IconData _icon(String name) => switch (name) {
        'shield' => Icons.shield_outlined,
        'overdue' => Icons.schedule_outlined,
        'today' => Icons.today_outlined,
        'chart' => Icons.insights_outlined,
        'rank' => Icons.leaderboard_outlined,
        _ => Icons.person_search_outlined,
      };
}

/// Aggregates, distributions and relationships, by table.
///
/// The subtitle counts what is measurable and what is groupable rather than
/// naming the table's columns: those two numbers are what decide whether a
/// question about this table is even possible, and they say it in four words.
class _ChartsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return ListView(
      padding: EdgeInsets.all(m.spaceLg),
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(bottom: m.spaceMd),
          child: Text(
            'Any number in the register can be counted, averaged or plotted '
            'against any category. The shape is chosen from the data — ask for '
            'a pie or a line by name to override it.',
            style: context.texts.bodySmall?.copyWith(
              color: context.palette.onSurfaceMuted,
            ),
          ),
        ),
        for (final group in AnalysisExamples.groups)
          if (group.examples.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceMd),
              child: SectionCard(
                title: group.title,
                subtitle: group.subtitle,
                leading: const Icon(Icons.query_stats_outlined, size: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final example in group.examples)
                      _QuestionRow(
                        question: example.question,
                        detail: example.shows,
                        icon: DataChart.iconFor(example.style),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// Every field, and the words that reach it.
///
/// The reference rather than the tour. It exists because the honest answer to
/// "what can I ask?" is a list, and hiding the list behind cheerful examples
/// leaves the one person who wanted to know whether `capillary refill` is in
/// there with no way to find out.
class _FieldsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return ListView(
      padding: EdgeInsets.all(m.spaceLg),
      children: <Widget>[
        for (final table in FieldRegistry.tables)
          Padding(
            padding: EdgeInsets.only(bottom: m.spaceSm),
            child: SectionCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: EdgeInsets.symmetric(horizontal: m.spaceMd),
                childrenPadding: EdgeInsets.fromLTRB(
                  m.spaceMd,
                  0,
                  m.spaceMd,
                  m.spaceMd,
                ),
                leading: Icon(_tableIcon(table.name), size: 20),
                title: Text(
                  _titleCase(table.label),
                  style: context.texts.labelLarge,
                ),
                subtitle: Text(
                  table.synonyms.take(3).join(' · '),
                  style: context.texts.labelSmall?.copyWith(
                    color: context.palette.onSurfaceMuted,
                  ),
                ),
                children: <Widget>[
                  for (final kind in <FieldKind>[
                    FieldKind.numeric,
                    FieldKind.categorical,
                    FieldKind.boolean,
                    FieldKind.temporal,
                    FieldKind.identifier,
                    FieldKind.text,
                  ])
                    if (table.ofKind(kind).isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(bottom: m.spaceSm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _kindLabel(kind),
                              style: context.texts.labelSmall?.copyWith(
                                color: context.palette.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: m.spaceXs),
                            Wrap(
                              spacing: m.spaceXs,
                              runSpacing: m.spaceXs,
                              children: <Widget>[
                                for (final field in table.ofKind(kind))
                                  Tooltip(
                                    message: field.synonyms.isEmpty
                                        ? field.label
                                        : 'Also: ${field.synonyms.take(4).join(', ')}',
                                    child: Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(
                                        field.unit == null
                                            ? field.label
                                            : '${field.label} (${field.unit})',
                                        style: context.texts.labelSmall,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// What each kind can be used *for*, which is the only thing worth saying
  /// about it. "Numeric" is a fact about storage; "can be averaged" is a fact
  /// about what you can ask.
  static String _kindLabel(FieldKind kind) => switch (kind) {
        FieldKind.numeric => 'Can be averaged, summed or plotted',
        FieldKind.categorical => 'Can be grouped by',
        FieldKind.boolean => 'Yes or no',
        FieldKind.temporal => 'Can be a timeline',
        FieldKind.identifier => 'Shown in lists, never charted',
        FieldKind.text => 'Searched for words, never charted',
      };

  static IconData _tableIcon(String name) => switch (name) {
        'patients' => Icons.people_outline,
        'encounters' => Icons.medical_information_outlined,
        'appointments' => Icons.event_outlined,
        'vitals' => Icons.monitor_heart_outlined,
        'clinical_notes' => Icons.description_outlined,
        'medications' => Icons.medication_outlined,
        'problems' => Icons.coronavirus_outlined,
        'allergies' => Icons.warning_amber_outlined,
        _ => Icons.attach_file_outlined,
      };

  static String _titleCase(String value) => Fmt.titleCase(value);
}

/// One tappable question.
///
/// Returns the text rather than running it, and the Ask page loads it into the
/// box. Two reasons: the useful version of a suggestion is almost always a
/// narrowed one, and a question that appears in the input can be seen to be
/// the question that was asked.
class _QuestionRow extends StatelessWidget {
  const _QuestionRow({
    required this.question,
    this.detail,
    this.icon,
  });

  final String question;
  final String? detail;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return InkWell(
      onTap: () => Navigator.of(context).pop(question),
      borderRadius: BorderRadius.circular(m.radiusSm),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: m.spaceXs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon ?? Icons.north_east,
              size: 15,
              color: palette.accent,
            ),
            SizedBox(width: m.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(question, style: context.texts.bodySmall),
                  if (detail case final detail?)
                    Text(
                      detail,
                      style: context.texts.labelSmall?.copyWith(
                        color: palette.onSurfaceMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
