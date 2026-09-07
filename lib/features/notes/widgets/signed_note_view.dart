import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/clinical_note.dart';

/// The banner shown above a signed note: who signed it and when, and a loud
/// warning if the stored content no longer matches its signature.
class SignatureBar extends StatelessWidget {
  const SignatureBar({super.key, required this.note});

  final ClinicalNote note;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final intact = note.verifyIntegrity();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: m.spaceLg,
        vertical: m.spaceSm,
      ),
      color: intact ? palette.surfaceSunken : palette.criticalSubtle,
      child: Row(
        children: <Widget>[
          Icon(
            intact ? Icons.verified_outlined : Icons.gpp_bad_outlined,
            size: 16,
            color: intact ? palette.signedLock : palette.critical,
          ),
          SizedBox(width: m.spaceSm),
          Expanded(
            child: Text(
              intact
                  ? 'Signed by ${note.signedBy ?? 'unknown'} · '
                      '${Fmt.dateTime(note.signedAt)}'
                  : 'Integrity check failed — stored content does not match '
                      'the signature',
              style: context.texts.labelSmall?.copyWith(
                color: intact ? palette.onSurfaceMuted : palette.critical,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The corrections appended after signing, each with its reason and author.
/// The original text is never touched; amendments only ever add.
class AmendmentList extends StatelessWidget {
  const AmendmentList({super.key, required this.amendments});

  final List<NoteAmendment> amendments;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SectionCard(
      title: 'Amendments',
      subtitle: 'Appended after signing — the original text is unchanged',
      leading: const Icon(Icons.playlist_add_check_outlined, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: amendments.map((amendment) {
          return Padding(
            padding: EdgeInsets.only(bottom: m.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${Fmt.dateTime(amendment.createdAt)} · '
                  '${amendment.author ?? 'unknown'}',
                  style: context.texts.labelSmall,
                ),
                Text(
                  'Reason: ${amendment.reason}',
                  style: context.texts.labelMedium,
                ),
                SizedBox(height: m.spaceXs),
                Text(amendment.body, style: context.texts.bodyMedium),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
