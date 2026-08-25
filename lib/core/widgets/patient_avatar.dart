import 'package:flutter/material.dart';

import '../theme/theme_config.dart';
import '../theme/theme_scope.dart';

/// A patient's initials on a stable, per-chart colour.
///
/// The colour is derived from the patient id, so it never changes and never
/// implies anything clinical — it exists purely so a long list of names is
/// scannable at a glance.
class PatientAvatar extends StatelessWidget {
  const PatientAvatar({
    super.key,
    required this.initials,
    required this.seed,
    this.radius = 22,
    this.badge,
  });

  final String initials;
  final String seed;
  final double radius;

  /// Optional corner marker, e.g. an allergy warning.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tone = palette.avatarToneFor(seed);

    final avatar = Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: context.iconTintAlpha),
        shape: BoxShape.circle,
        border: Border.all(color: tone.withValues(alpha: 0.40), width: 1.5),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: tone,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.72,
          height: 1,
        ),
      ),
    );

    if (badge == null) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        avatar,
        Positioned(right: -2, bottom: -2, child: badge!),
      ],
    );
  }
}

/// Small circular warning marker used on avatars.
class AvatarBadge extends StatelessWidget {
  const AvatarBadge({super.key, required this.icon, required this.tone});

  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.surface,
        shape: BoxShape.circle,
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
        child: Icon(icon, size: 9, color: palette.surface),
      ),
    );
  }
}

/// Convenience for reading a tone directly.
Color avatarTone(ClinicalPalette palette, String seed) =>
    palette.avatarToneFor(seed);
