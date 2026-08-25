import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import 'capability_sheet.dart';

/// The empty state: an invitation, not a manual.
///
/// What replaced five cards of examples. Those cards were the guide, and a
/// guide that is always on screen has two problems — nobody reads it twice,
/// and sitting in the same cards as the answers it was indistinguishable from
/// them, so the page looked like it was permanently showing results.
///
/// One line about what this does, and one button to the whole capability list.
/// The aurora behind it is doing real work: it marks this surface as the
/// generated one, so the visual language announces what kind of page this is
/// before anything is typed.
class AskIntro extends StatelessWidget {
  const AskIntro({super.key, required this.onQuestion});

  /// Hands a tapped starter back to the screen, which owns the input box. A
  /// plain callback rather than an InheritedWidget: there is exactly one
  /// caller, and indirection for one caller is just distance.
  final ValueChanged<String> onQuestion;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return AiAuroraBackground(
      intensity: 0.85,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(m.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const AiSparkleIcon(size: 44),
              SizedBox(height: m.spaceMd),
              Text(
                'Ask about the register',
                style: context.texts.titleMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: m.spaceSm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  'Recall lists, overdue reviews, counts, averages and charts '
                  '— in your own words. Every answer shows what it searched '
                  'and what it left out.',
                  textAlign: TextAlign.center,
                  style: context.texts.bodySmall?.copyWith(
                    color: palette.onSurfaceMuted,
                  ),
                ),
              ),
              SizedBox(height: m.spaceLg),
              // Bordered rather than filled. The primary action on this page
              // is the text field; this is the way in for someone who does not
              // yet know what to type, and it must not outrank it.
              OutlinedButton.icon(
                onPressed: () async {
                  final chosen = await CapabilitySheet.show(context);
                  // Handed back up rather than reaching across into the
                  // controller from here — the screen owns the box.
                  if (chosen != null && context.mounted) onQuestion(chosen);
                },
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('What can I ask?'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
