import 'package:flutter/material.dart';
import 'package:opt_kit/opt_kit.dart' show OptDetailRow;

import '../theme/theme_config.dart' show ClinicalPaletteX;
import '../theme/theme_scope.dart';
import '../widgets/patient_avatar.dart';
import '../widgets/status_pill.dart';

/// Composite patterns.
///
/// These exist so screens stop hand-assembling the same `Row` of avatar, two
/// lines of text and a trailing pill. Every list of people in the app should
/// look identical; the way to guarantee that is to have exactly one
/// implementation.

/// A person in a list: avatar, name, identity line, optional trailing status.
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.name,
    required this.subtitle,
    required this.seed,
    required this.initials,
    this.trailing,
    this.trailingLabel,
    this.trailingTone = PillTone.neutral,
    this.badge,
    this.onTap,
    this.dense = false,
  });

  final String name;
  final String subtitle;

  /// Stable identifier used to pick the avatar colour — pass the record id,
  /// never the name, so renaming a patient does not recolour them.
  final String seed;
  final String initials;

  final Widget? trailing;
  final String? trailingLabel;
  final PillTone trailingTone;
  final Widget? badge;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: dense,
      onTap: onTap,
      leading: PatientAvatar(
        initials: initials,
        seed: seed,
        radius: dense ? 16 : 20,
        badge: badge,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ??
          (trailingLabel == null
              ? null
              : StatusPill(
                  label: trailingLabel!,
                  tone: trailingTone,
                  dense: true,
                )),
    );
  }
}

/// Label/value line used inside detail panels.
///
/// A thin wrapper over the kit's family-canonical [OptDetailRow] — one shared
/// implementation of the label/value row across the OptERP suite. The local
/// name and constructor are kept so call sites don't churn. The kit row reads
/// `Theme.of(context).colorScheme`, which this app populates from its JSON
/// tokens, so colours stay tokenized. Note it carries the family's own edge
/// padding (16 horizontal / 12 vertical), so detail panels adopt the family
/// rhythm rather than this app's former tighter one.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 96,
  });

  final String label;
  final String value;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return OptDetailRow(label: label, value: value, labelWidth: labelWidth);
  }
}

/// A small number-plus-label chip, for counts that are context rather than
/// actions.
class MetricChip extends StatelessWidget {
  const MetricChip({
    super.key,
    required this.label,
    required this.value,
    this.tone,
  });

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final colour = tone ?? palette.onSurfaceMuted;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: m.spaceMd,
        vertical: m.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: context.iconTintAlpha * 0.7),
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            style: context.texts.titleMedium?.copyWith(
              color: colour,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(width: m.spaceXs + 2),
          Text(label, style: context.texts.labelSmall),
        ],
      ),
    );
  }
}

/// A prominent, tinted callout — used for the dashboard's alert block and
/// anywhere a whole section needs to read as urgent.
class Callout extends StatelessWidget {
  const Callout({
    super.key,
    required this.title,
    required this.icon,
    required this.tone,
    this.subtitle,
    required this.child,
  });

  final String title;
  final IconData icon;

  /// Should come from the clinical severity palette — this is a signal, not
  /// decoration.
  final Color tone;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Container(
      padding: EdgeInsets.all(m.spaceLg),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: context.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(m.radiusMd),
        border: Border.all(
          color: tone.withValues(alpha: 0.28),
          width: m.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: tone, size: 20),
              SizedBox(width: m.spaceSm),
              Expanded(
                child: Text(
                  title,
                  style: context.texts.titleMedium?.copyWith(color: tone),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...<Widget>[
            SizedBox(height: m.spaceXs),
            Text(subtitle!, style: context.texts.bodySmall),
          ],
          SizedBox(height: m.spaceSm),
          child,
        ],
      ),
    );
  }
}

/// Full-width primary surface used for the single most important thing on a
/// screen — the dashboard's "next patient", for example.
class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.child,
    this.tone,
    this.onSurfaceTone,
  });

  final Widget child;
  final Color? tone;
  final Color? onSurfaceTone;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.spaceLg),
      decoration: BoxDecoration(
        // A brand/hero surface carries the family warm→cool sweep. An explicit
        // [tone] override (a caller wanting a flat fill) still wins.
        color: tone,
        gradient: tone == null ? palette.heroGradient : null,
        borderRadius: BorderRadius.circular(m.radiusMd),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: onSurfaceTone ?? palette.onHeroSurface),
        child: child,
      ),
    );
  }
}
