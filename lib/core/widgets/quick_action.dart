import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// One tap-target on the dashboard's quick-action grid.
///
/// These are the handful of things a clinician starts a session by doing.
/// Making them large, labelled and always in the same place matters more than
/// making them pretty: the target is muscle memory, not discovery.
class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Defaults to the theme accent when omitted.
  final Color? tone;

  /// Optional count bubble, e.g. patients currently waiting.
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final color = tone ?? palette.accent;

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(m.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: m.spaceMd,
            vertical: m.spaceLg,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: context.iconTintAlpha),
                      borderRadius: BorderRadius.circular(m.radiusSm + 2),
                      border: Border.all(
                        color: color.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Icon(icon, size: 24, color: color),
                  ),
                  if (badgeCount != null && badgeCount! > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        constraints: const BoxConstraints(minWidth: 20),
                        decoration: BoxDecoration(
                          color: palette.critical,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: palette.surface, width: 2),
                        ),
                        child: Text(
                          '$badgeCount',
                          textAlign: TextAlign.center,
                          style: context.texts.labelSmall?.copyWith(
                            color: palette.onCritical,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: m.spaceSm + 2),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelMedium?.copyWith(height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
