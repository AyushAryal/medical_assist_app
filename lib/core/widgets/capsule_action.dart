import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// A compact tinted capsule action — the iOS gesture for "useful, secondary".
///
/// Where an outlined Material button is a 48px bordered slab, this is a small
/// stadium of tint with the label carrying the colour: quiet in a row of four,
/// still unmistakably tappable. The tap target is padded back up to 44px by
/// the outer padding, so small never means fiddly.
class CapsuleAction extends StatelessWidget {
  const CapsuleAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.tint,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  /// Defaults to the primary colour; pass another palette tone where the
  /// action's meaning has one (never a severity colour for decoration).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final colour = tint ?? palette.primary;
    final enabled = onTap != null;
    final fg = enabled ? colour : palette.onSurfaceMuted;

    return Material(
      color: fg.withValues(alpha: context.isDark ? 0.16 : 0.10),
      borderRadius: BorderRadius.circular(m.radiusLg * 2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: m.spaceMd,
            vertical: m.spaceXs + 3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: fg),
              SizedBox(width: m.spaceXs + 2),
              Text(
                label,
                style: context.texts.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
