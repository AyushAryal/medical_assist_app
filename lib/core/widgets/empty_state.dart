import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// Empty states say what to do next, not just that there is nothing here.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: m.spaceXl,
        vertical: compact ? m.spaceLg : m.space2xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: compact ? 28 : 40,
            color: palette.onSurfaceMuted,
          ),
          SizedBox(height: m.spaceMd),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.texts.titleSmall,
          ),
          if (message != null) ...<Widget>[
            SizedBox(height: m.spaceXs),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: context.texts.bodySmall,
            ),
          ],
          if (actionLabel != null && onAction != null) ...<Widget>[
            SizedBox(height: m.spaceLg),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
