import 'package:flutter/material.dart';

import '../../../ai/presentation.dart';
import '../../../core/design/design.dart';

/// A change waiting for a person to accept it.
///
/// This view describes; it never acts. Confirmation lives with the caller,
/// goes through the repository like any other write, and is audited
/// identically — there is no second-class path into a medical record.
class ProposalAnswerView extends StatelessWidget {
  const ProposalAnswerView({super.key, required this.result});

  final ProposalPresentation result;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Callout(
      title: result.isBlocked
          ? 'Cannot be done from here'
          : 'Nothing has changed yet',
      icon: result.isBlocked ? Icons.lock_outline : Icons.edit_note,
      tone: result.isBlocked ? palette.onSurfaceMuted : palette.caution,
      subtitle: result.blockedReason ??
          'Check each line before accepting. Accepting writes to the '
              'record and is logged like any other change.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final change in result.changes)
            DetailRow(
              label: change.field,
              value: change.from == '—'
                  ? change.to
                  : '${change.from}  →  ${change.to}',
            ),
          if (!result.isBlocked) ...<Widget>[
            SizedBox(height: m.spaceSm),
            Text(
              'Accepting is a deliberate step — see ${result.confirmLabel}.',
              style: context.texts.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}
