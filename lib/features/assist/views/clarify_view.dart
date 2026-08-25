import 'package:flutter/material.dart';

import '../../../ai/presentation.dart';
import '../../../core/design/design.dart';

/// The assistant's question, with its answers as buttons.
///
/// Options run immediately on tap — they are answers to a question the
/// assistant itself just asked, and making someone confirm their own answer
/// turns a dialogue back into a form. (Suggestions after a *failure* still
/// load the box instead; the difference is who asked the question.)
class ClarifyAnswerView extends StatelessWidget {
  const ClarifyAnswerView({
    super.key,
    required this.result,
    required this.onPick,
  });

  final ClarifyPresentation result;

  /// Runs the chosen question. Null renders the options inert, which only
  /// happens in contexts that cannot ask (and should not show this).
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Wrap(
      spacing: m.spaceSm,
      runSpacing: m.spaceXs,
      children: <Widget>[
        for (final option in result.options)
          ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              Icons.reply,
              size: 14,
              color: context.palette.accent,
            ),
            label: Text(option.label, style: context.texts.labelSmall),
            onPressed:
                onPick == null ? null : () => onPick!(option.question),
          ),
      ],
    );
  }
}
