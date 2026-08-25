import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/design.dart';
import '../../data/services/assist/note_drafting.dart';

/// What to do with a generated patient-instructions draft.
enum InstructionsAction { dismissed, appended, copied }

/// The plan, reworded for the patient.
///
/// Unlike the SOAP sort, this text is genuinely generated — new words are the
/// whole point — so it cannot be gated word-for-word and the caveat does that
/// work instead. It stays visibly generated until a clinician has read it
/// against the plan, and there is no path from here to a signed note that
/// skips that reading.
class PatientInstructionsSheet extends StatelessWidget {
  const PatientInstructionsSheet({
    super.key,
    required this.draft,
    required this.plan,
  });

  final InstructionsDraft draft;

  /// The plan it was reworded from, shown beside it — checking a rewording
  /// against remembered text is not checking.
  final String plan;

  static Future<InstructionsAction> show(
    BuildContext context, {
    required InstructionsDraft draft,
    required String plan,
  }) async {
    final action = await showModalBottomSheet<InstructionsAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (context) =>
          PatientInstructionsSheet(draft: draft, plan: plan),
    );
    return action ?? InstructionsAction.dismissed;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const AiSparkleIcon(size: 20),
                SizedBox(width: m.spaceSm),
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
              'Written by ${draft.engineName} from your plan. This one is '
              'generated rather than rearranged, so read every line against '
              'the plan before it goes anywhere.',
              style: context.texts.labelSmall,
            ),
            SizedBox(height: m.spaceMd),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Your plan',
                      style: context.texts.labelSmall
                          ?.copyWith(color: palette.onSurfaceMuted),
                    ),
                    SizedBox(height: m.spaceXs),
                    Container(
                      padding: EdgeInsets.all(m.spaceSm),
                      decoration: BoxDecoration(
                        color: palette.surfaceMuted,
                        borderRadius: BorderRadius.circular(m.radiusSm),
                      ),
                      child: Text(plan, style: context.texts.bodySmall),
                    ),
                    SizedBox(height: m.spaceMd),
                    Text(
                      'Reworded',
                      style: context.texts.labelSmall
                          ?.copyWith(color: palette.onSurfaceMuted),
                    ),
                    SizedBox(height: m.spaceXs),
                    Container(
                      padding: EdgeInsets.all(m.spaceMd),
                      decoration: BoxDecoration(
                        color: palette.accentSubtle,
                        borderRadius: BorderRadius.circular(m.radiusSm),
                        border: Border.all(
                          color: palette.accent.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        draft.text,
                        style: context.texts.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: m.spaceMd),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: draft.text));
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
