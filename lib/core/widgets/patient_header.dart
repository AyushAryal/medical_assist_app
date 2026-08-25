import 'package:flutter/material.dart';

import '../../data/models/allergy.dart';
import '../../data/models/patient.dart';
import '../theme/theme_scope.dart';
import 'status_pill.dart';

/// The identity strip pinned to the top of every clinical screen.
///
/// Wrong-patient error is one of the most common and most damaging mistakes in
/// clinical software. Name, age, sex and MRN stay visible on every screen that
/// can write to a chart, so there is never a moment where the user is entering
/// data without being told whose record it is going into.
class PatientIdentityBar extends StatelessWidget {
  const PatientIdentityBar({
    super.key,
    required this.patient,
    this.onTap,
    this.trailing,
  });

  final Patient patient;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return Material(
      color: palette.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: m.spaceLg,
            vertical: m.spaceMd,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: palette.outline, width: m.borderWidth),
            ),
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: palette.primaryContainer,
                child: Text(
                  patient.initials,
                  style: context.texts.labelLarge
                      ?.copyWith(color: palette.onPrimaryContainer),
                ),
              ),
              SizedBox(width: m.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            patient.displayName,
                            style: context.texts.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (patient.isDeceased) ...<Widget>[
                          SizedBox(width: m.spaceSm),
                          const StatusPill(
                            label: 'Deceased',
                            tone: PillTone.neutral,
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      patient.identityLine,
                      style: context.texts.bodySmall?.copyWith(
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// The allergy banner.
///
/// Three states, and all three are shown — including "not recorded". A blank
/// space reads as "no allergies" to a hurried clinician, which is precisely
/// the assumption that gets a patient given a drug they react to.
class AllergyBanner extends StatelessWidget {
  const AllergyBanner({
    super.key,
    required this.status,
    required this.allergies,
    this.onTap,
  });

  final AllergyStatus status;
  final List<Allergy> allergies;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    final active = allergies.where((a) => a.isActive).toList();
    final highRisk = active.any((a) => a.severity.isHighRisk);

    final (background, foreground, icon, text) = switch (status) {
      AllergyStatus.hasAllergies when active.isNotEmpty => (
          highRisk ? palette.allergyBanner : palette.cautionSubtle,
          highRisk ? palette.onAllergyBanner : palette.caution,
          Icons.warning_amber_rounded,
          'ALLERGY: ${active.map((a) => a.substance).join(', ')}',
        ),
      AllergyStatus.noKnownAllergies => (
          palette.normalSubtle,
          palette.normal,
          Icons.check_circle_outline,
          'No known allergies',
        ),
      _ => (
          palette.surfaceSunken,
          palette.onSurfaceMuted,
          Icons.help_outline,
          'Allergies not recorded — ask the patient',
        ),
    };

    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: m.spaceLg,
            vertical: m.spaceSm,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 18, color: foreground),
              SizedBox(width: m.spaceSm),
              Expanded(
                child: Text(
                  text,
                  style: context.texts.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 18, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
