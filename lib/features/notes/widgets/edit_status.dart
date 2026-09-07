import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../core/utils/formatters.dart';

/// The autosave indicator under the fields: "Saving…" while dirty, otherwise
/// the time of the last save (or the reassurance that it happens on its own).
class SaveStatus extends StatelessWidget {
  const SaveStatus({super.key, required this.dirty, required this.savedAt});

  final bool dirty;
  final DateTime? savedAt;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          dirty ? Icons.sync : Icons.cloud_done_outlined,
          size: 14,
          color: palette.onSurfaceMuted,
        ),
        SizedBox(width: m.spaceXs),
        Text(
          dirty
              ? 'Saving…'
              : savedAt == null
                  ? 'Autosaves as you type'
                  : 'Saved ${Fmt.time(savedAt)}',
          style: context.texts.labelSmall,
        ),
      ],
    );
  }
}

/// "That was inserted — you can take it back", with a timer this app owns.
class UndoBanner extends StatelessWidget {
  const UndoBanner({
    super.key,
    required this.message,
    required this.onUndo,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      margin: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceXs),
      padding: EdgeInsets.fromLTRB(m.spaceMd, m.spaceSm, m.spaceXs, m.spaceSm),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
        border: Border.all(color: palette.outline, width: m.hairline),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.history, size: 16, color: palette.onSurfaceMuted),
          SizedBox(width: m.spaceSm),
          Expanded(
            child: Text(message, style: context.texts.bodySmall),
          ),
          TextButton(
            onPressed: onUndo,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Undo'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
