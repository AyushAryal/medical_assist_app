import 'package:flutter/material.dart';

import '../../../ai/presentation.dart';
import '../../../core/design/design.dart';

/// Nothing to show, and what to try instead.
///
/// The suggestions load the box for editing rather than firing — a failed
/// question is exactly the moment someone wants to adjust wording, not watch
/// another guess run itself.
class MessageAnswerView extends StatelessWidget {
  const MessageAnswerView({
    super.key,
    required this.result,
    this.onSuggestion,
  });

  final MessagePresentation result;
  final ValueChanged<String>? onSuggestion;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    if (result.suggestions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: m.spaceSm),
      child: Wrap(
        spacing: m.spaceXs,
        runSpacing: m.spaceXs,
        children: <Widget>[
          for (final suggestion in result.suggestions)
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.north_west, size: 13),
              label: Text(suggestion, style: context.texts.labelSmall),
              onPressed: () => onSuggestion?.call(suggestion),
            ),
        ],
      ),
    );
  }
}
