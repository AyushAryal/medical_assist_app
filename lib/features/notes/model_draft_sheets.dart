import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/design.dart';
import '../../data/services/assist/note_drafting.dart';

/// Preview of a model-sorted note, accepted or discarded as a whole.
///
/// The preview is the second gate. The mechanical one in [NoteDrafting]
/// checked that no words were invented and none lost; this one puts the
/// result in front of the person who owns the record, badge on, before a
/// character of it touches the note. Nothing is applied on a swipe-away.
class SoapSortSheet extends StatelessWidget {
  const SoapSortSheet({super.key, required this.draft});

  final SoapDraft draft;

  static Future<bool> show(BuildContext context, SoapDraft draft) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SoapSortSheet(draft: draft),
    );
    return accepted ?? false;
  }

  static const Map<String, String> _titles = <String, String>{
    'subjective': 'Subjective',
    'objective': 'Objective',
    'assessment': 'Assessment',
    'plan': 'Plan',
  };

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Sorted into sections',
                    style: context.texts.titleMedium,
                  ),
                ),
                const AiBadge(dense: true),
              ],
            ),
            SizedBox(height: m.spaceXs),
            Text(
              'Your words, unchanged — checked mechanically — sorted by '
              '${draft.engineName}. Read each box; accepting replaces the '
              'sections below with these.',
              style: context.texts.labelSmall,
            ),
            SizedBox(height: m.spaceMd),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final key in NoteDrafting.sectionKeys)
                      if (draft.sections[key] case final text?)
                        Padding(
                          padding: EdgeInsets.only(bottom: m.spaceSm),
                          child: SectionCard(
                            title: _titles[key],
                            child: Text(
                              text,
                              style: context.texts.bodySmall,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
            SizedBox(height: m.spaceSm),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Keep as it was'),
                  ),
                ),
                SizedBox(width: m.spaceSm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Use this sort'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What to do with a generated patient-instructions draft.
enum InstructionsAction { dismissed, appended, copied }

/// Preview of the plan reworded for the patient.
///
/// Unlike the sort, this text is genuinely generated — new words are the
/// point — so it cannot be gated mechanically and the caveat does the work
/// instead: it stays a draft until the clinician has read it against the
/// plan, and the badge stays on it.
class PatientInstructionsSheet extends StatelessWidget {
  const PatientInstructionsSheet({super.key, required this.draft});

  final InstructionsDraft draft;

  static Future<InstructionsAction> show(
    BuildContext context,
    InstructionsDraft draft,
  ) async {
    final action = await showModalBottomSheet<InstructionsAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => PatientInstructionsSheet(draft: draft),
    );
    return action ?? InstructionsAction.dismissed;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'For the patient',
                    style: context.texts.titleMedium,
                  ),
                ),
                const AiBadge(dense: true),
              ],
            ),
            SizedBox(height: m.spaceXs),
            Text(
              'Reworded by ${draft.engineName}. Generated text — check every '
              'instruction against the plan before it goes anywhere.',
              style: context.texts.labelSmall,
            ),
            SizedBox(height: m.spaceMd),
            Flexible(
              child: SingleChildScrollView(
                child: AiGlowBorder(
                  active: true,
                  child: Padding(
                    padding: EdgeInsets.all(m.spaceMd),
                    child: Text(draft.text, style: context.texts.bodyMedium),
                  ),
                ),
              ),
            ),
            SizedBox(height: m.spaceMd),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: draft.text),
                      );
                      if (context.mounted) {
                        Navigator.of(context).pop(InstructionsAction.copied);
                      }
                    },
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
                SizedBox(width: m.spaceSm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(InstructionsAction.appended),
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: const Text('Add to plan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
