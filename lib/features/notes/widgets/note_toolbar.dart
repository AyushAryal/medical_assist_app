import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

/// The three bulk actions, spelled out.
///
/// These were icon-only buttons in the app bar: a page icon for "insert
/// template" and a copy icon for "copy forward". Neither is guessable — the
/// page icon is used for documents, articles, notes and lists across the
/// platform, and a copy icon in a text editor means copy the text. An action
/// that rewrites four fields cannot be behind a glyph the user has to tap to
/// learn. They are labelled, and they sit above the fields they change.
class NoteToolbar extends StatelessWidget {
  const NoteToolbar({
    super.key,
    required this.onTemplate,
    required this.onCopyForward,
    required this.onDictate,
  });

  final VoidCallback onTemplate;
  final VoidCallback onCopyForward;
  final VoidCallback onDictate;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: m.spaceLg,
        vertical: m.spaceSm,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        border: Border(
          bottom: BorderSide(color: palette.outline, width: m.hairline),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            _ToolbarButton(
              icon: Icons.mic_none_outlined,
              label: 'Dictate',
              onPressed: onDictate,
              emphasised: true,
            ),
            SizedBox(width: m.spaceSm),
            _ToolbarButton(
              icon: Icons.dashboard_customize_outlined,
              label: 'Template',
              onPressed: onTemplate,
            ),
            SizedBox(width: m.spaceSm),
            _ToolbarButton(
              icon: Icons.history_edu_outlined,
              label: 'Copy forward',
              onPressed: onCopyForward,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      foregroundColor:
          emphasised ? context.palette.primary : context.palette.onSurface,
    );
    return emphasised
        ? FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
          )
        : TextButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }
}
