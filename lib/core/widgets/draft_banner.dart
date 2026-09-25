import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// The "Draft restored · Discard" affordance shown when a kit `DraftGroup`
/// reapplied an interrupted form's values on open.
///
/// Visually the same row as `OptSheetScaffold`'s built-in banner (history
/// icon, muted label, compact Discard action) so drafts speak with one voice
/// across the family — but drawn from this app's palette tokens, because the
/// app's own `SheetScaffold` hosts it here.
class DraftRestoredRow extends StatelessWidget {
  const DraftRestoredRow({super.key, required this.onDiscard});

  /// Undoes the restore and deletes the stored draft — wire this to
  /// `DraftGroup.discardRestored()` plus a `setState` hiding the row.
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceSm),
      child: Row(
        children: <Widget>[
          Icon(Icons.history, size: 16, color: palette.onSurfaceMuted),
          SizedBox(width: m.spaceXs),
          Expanded(
            child: Text(
              'Draft restored',
              style: context.texts.bodySmall
                  ?.copyWith(color: palette.onSurfaceMuted),
            ),
          ),
          TextButton(
            onPressed: onDiscard,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.symmetric(horizontal: m.spaceSm),
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}
