import 'package:flutter/material.dart';
import '../../../ai/presentation.dart';
import '../../../core/design/design.dart';
import 'data_table_card.dart';
import 'support.dart';
/// A count with the records behind it.
///
/// Two renderings of the same rows. The list is people you can tap through to
/// a chart — the default, because acting on an answer means opening a record.
/// The table adds the projected columns — what "patients and their contact
/// numbers" or a ranking's measured value asked for — and its rows open the
/// same charts.
class MetricAnswerView extends StatelessWidget {
  const MetricAnswerView({
    super.key,
    required this.result,
    required this.view,
    required this.compact,
    required this.rowLimit,
    this.onExpand,
  });
  final MetricPresentation result;
  final ResultView view;
  final bool compact;
  final int rowLimit;
  final VoidCallback? onExpand;
  @override
  Widget build(BuildContext context) {
    return view == ResultView.table && result.cells.isNotEmpty
        ? _table(context)
        : _list(context);
  }
  Widget _list(BuildContext context) {
    final m = context.metrics;
    final rows = result.rows.take(rowLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HeroPanel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '${result.value}',
                style: (compact
                        ? context.texts.headlineMedium
                        : context.texts.displaySmall)
                    ?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              SizedBox(width: m.spaceSm),
              Padding(
                padding: EdgeInsets.only(bottom: m.spaceXs),
                child: Text(
                  '${result.label}${result.value == 1 ? '' : 's'}',
                  style: context.texts.titleSmall,
                ),
              ),
            ],
          ),
        ),
        if (rows.isNotEmpty) ...<Widget>[
          SizedBox(height: m.spaceSm),
          for (var i = 0; i < rows.length; i++)
            PersonRow(
              name: rows[i].patient.displayName,
              // The projected value earns the subtitle in list mode too: a
              // ranking by NEWS2 whose list hides the score answers less than
              // its own table.
              subtitle: i < result.cells.length && result.cells[i].isNotEmpty
                  ? result.cells[i].join(' · ')
                  : rows[i].detail ?? rows[i].patient.identityLine,
              seed: rows[i].patient.id,
              initials: rows[i].patient.initials,
              dense: compact,
              onTap: () => openChart(rows[i].patient.id),
            ),
          if ((result.total ?? rows.length) > rows.length)
            SeeAllFooter(
              label: '${result.total} in total',
              onExpand: onExpand,
            ),
        ],
      ],
    );
  }
  Widget _table(BuildContext context) {
    final rows = result.rows.take(rowLimit).toList();
    return AnswerTableCard(
      title: '${result.value} ${result.label}${result.value == 1 ? '' : 's'}',
      leading: const Icon(Icons.people_outline, size: 20),
      columns: <String>['Patient', ...result.columns],
      rows: <List<String>>[
        for (var i = 0; i < rows.length; i++)
          <String>[
            rows[i].patient.displayName,
            ...(i < result.cells.length
                ? result.cells[i]
                : List<String>.filled(result.columns.length, '—')),
          ],
      ],
      onTapRow: (index) => openChart(rows[index].patient.id),
      footer: (result.total ?? rows.length) > rows.length
          ? SeeAllFooter(
              label: '${result.total} in total',
              onExpand: onExpand,
            )
          : null,
    );
  }
}
