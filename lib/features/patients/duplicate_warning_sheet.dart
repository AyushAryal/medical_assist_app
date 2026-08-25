import 'package:flutter/material.dart';

import '../../clinical/insights/duplicate_detector.dart';
import '../../core/design/design.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/patient.dart';

/// What the person at the desk decided.
class DuplicateChoice {
  const DuplicateChoice.registerAnyway() : openExistingId = null;

  const DuplicateChoice.openExisting(String this.openExistingId);

  /// Set when they recognised the patient and want the existing chart.
  final String? openExistingId;
}

/// "Is this the same person?", asked once, with the evidence.
///
/// Duplicate records are the most damaging routine data-quality failure in a
/// clinic register, and the damage is clinical: the allergy recorded on Tuesday
/// is not on the chart opened on Friday, and someone treated for years shows no
/// history at all.
///
/// The design constraint is that this sheet must never be an obstacle. It
/// cannot refuse, it cannot require a reason, and "register anyway" is always
/// available and always one tap — because the alternative is staff learning to
/// defeat it, which produces worse data than not checking. Its whole job is to
/// make the *existing* record easy to find at the one moment someone is about
/// to create a second one.
class DuplicateWarningSheet extends StatelessWidget {
  const DuplicateWarningSheet({
    super.key,
    required this.draft,
    required this.candidates,
  });

  final Patient draft;
  final List<DuplicateCandidate> candidates;

  static Future<DuplicateChoice?> show(
    BuildContext context, {
    required Patient draft,
    required List<DuplicateCandidate> candidates,
  }) {
    return showModalBottomSheet<DuplicateChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DuplicateWarningSheet(
        draft: draft,
        candidates: candidates,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final strong = candidates
        .where((c) => c.score >= DuplicateDetector.strongThreshold)
        .length;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          maxWidth: m.contentMaxWidth,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.person_search,
                        color: palette.caution,
                        size: 22,
                      ),
                      SizedBox(width: m.spaceSm),
                      Expanded(
                        child: Text(
                          candidates.length == 1
                              ? 'This may already be registered'
                              : '${candidates.length} records look similar',
                          style: context.texts.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: m.spaceXs),
                  Text(
                    strong > 0
                        ? 'Registering ${draft.fullName} again would split '
                            'their history across two charts. Check whether '
                            'one of these is them.'
                        : 'These are only similar, not necessarily the same '
                            'person. Names repeat within a family and within a '
                            'village.',
                    style: context.texts.bodySmall,
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(
                  m.spaceLg,
                  0,
                  m.spaceLg,
                  m.spaceMd,
                ),
                itemCount: candidates.length,
                separatorBuilder: (_, _) => SizedBox(height: m.spaceSm),
                itemBuilder: (context, index) =>
                    _CandidateCard(candidate: candidates[index]),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceLg),
              child: Column(
                children: <Widget>[
                  // Always available, always one tap. A duplicate check that
                  // can block registration is one staff learn to defeat.
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      const DuplicateChoice.registerAnyway(),
                    ),
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(
                      'This is someone else — register ${draft.givenName}',
                    ),
                  ),
                  SizedBox(height: m.spaceSm),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to the form'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate});

  final DuplicateCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final existing = candidate.existing;
    final isStrong = candidate.score >= DuplicateDetector.strongThreshold;

    return GlassPanel(
      padding: EdgeInsets.all(m.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              PatientAvatar(
                initials: _initialsOf(existing),
                seed: existing.id,
                radius: 20,
              ),
              SizedBox(width: m.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      existing.displayName,
                      style: context.texts.titleSmall,
                    ),
                    Text(
                      <String>[
                        if (existing.mrn?.isNotEmpty ?? false)
                          'MRN ${existing.mrn}',
                        if (existing.dateOfBirth != null)
                          existing.dobIsEstimated
                              ? 'born ~${existing.dateOfBirth!.year}'
                              : Fmt.date(existing.dateOfBirth),
                        if (existing.phone?.isNotEmpty ?? false)
                          existing.phone!,
                      ].join(' · '),
                      style: context.texts.bodySmall,
                    ),
                  ],
                ),
              ),
              const AiBadge(label: 'Matched', dense: true),
              SizedBox(width: m.spaceXs),
              StatusPill(
                label: candidate.isNearCertain
                    ? 'Same ID'
                    : isStrong
                        ? 'Likely'
                        : 'Possible',
                tone: candidate.isNearCertain || isStrong
                    ? PillTone.critical
                    : PillTone.caution,
                dense: true,
              ),
              InfoDot(
                explanation: DuplicateDetector.explain(candidate),
                semanticLabel: 'Why this record was suggested',
              ),
            ],
          ),
          SizedBox(height: m.spaceSm),
          Wrap(
            spacing: m.spaceXs,
            runSpacing: m.spaceXs,
            children: <Widget>[
              for (final reason in candidate.reasons)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: m.spaceSm,
                    vertical: m.spaceXs / 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surfaceMuted,
                    borderRadius: BorderRadius.circular(m.radiusXs),
                  ),
                  child: Text(reason, style: context.texts.labelSmall),
                ),
            ],
          ),
          SizedBox(height: m.spaceSm),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(
              DuplicateChoice.openExisting(existing.id),
            ),
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('This is them — open their chart'),
          ),
        ],
      ),
    );
  }

  /// The detector carries only the identity fields, not a full patient, so the
  /// initials are derived here rather than read off a model.
  static String _initialsOf(PatientIdentity identity) {
    final given =
        identity.givenName.isNotEmpty ? identity.givenName[0] : '';
    final family =
        identity.familyName.isNotEmpty ? identity.familyName[0] : '';
    final initials = '$given$family'.toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }
}
