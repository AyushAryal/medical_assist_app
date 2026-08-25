import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design.dart';
import '../../../core/routing/app_router.dart';

/// Opens a patient's chart from inside an answer.
///
/// Through the root navigator on purpose: answers render both on the Ask page
/// and inside the floating panel, and the panel is mounted above the router's
/// Navigator — its own context has no `push`. One helper, so no view has to
/// know which surface it is on.
void openChart(String patientId) {
  final context = AppRouter.rootNavigatorKey.currentContext;
  if (context != null && context.mounted) {
    context.push(Routes.chartFor(patientId));
  }
}

/// The truncation footer.
///
/// A truncated list must never be mistaken for a complete one, so every view
/// that caps its rows ends with this: the true total, and the way to the rest
/// where a fuller surface exists.
class SeeAllFooter extends StatelessWidget {
  const SeeAllFooter({super.key, required this.label, this.onExpand});

  final String label;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    if (onExpand == null) {
      return Padding(
        padding: EdgeInsets.only(top: context.metrics.spaceXs),
        child: Text(label, style: context.texts.labelSmall),
      );
    }
    return TextButton.icon(
      onPressed: onExpand,
      icon: const Icon(Icons.open_in_full, size: 16),
      label: Text('See all — $label'),
    );
  }
}

/// One caveat line under a result.
///
/// Caveats sit under the content rather than behind the info control. A folded
/// "Other" group or a part-finished final week changes how the picture should
/// be read, and a reader who has to go looking for that has already misread it.
class FootnoteLine extends StatelessWidget {
  const FootnoteLine(this.note, {super.key});

  final String note;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceXs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 12,
            color: context.palette.onSurfaceMuted,
          ),
          SizedBox(width: m.spaceXs),
          Expanded(
            child: Text(
              note,
              style: context.texts.labelSmall?.copyWith(
                color: context.palette.onSurfaceMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
