import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/design.dart';

/// What the reader needs to know before judging any of it.
class DraftPreamble extends StatelessWidget {
  const DraftPreamble({super.key, required this.engineName});

  final String engineName;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const AiSparkleIcon(size: 20),
        SizedBox(width: m.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'Sorted by $engineName',
                    style: context.texts.labelLarge,
                  ),
                  SizedBox(width: m.spaceXs),
                  const AiBadge(dense: true),
                ],
              ),
              SizedBox(height: m.spaceXs),
              Text(
                'Your sentences, filed — never reworded. Each one below is '
                'exactly what you dictated. Highlighted sentences are the ones '
                'the model filed rather than the rules, so check those first. '
                'Keep the sections you agree with; nothing changes until you '
                'apply.',
                style: context.texts.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The commit bar: what will happen, in a sentence, before it happens.
class ApplyBar extends StatelessWidget {
  const ApplyBar({
    super.key,
    required this.keeping,
    required this.total,
    required this.onApply,
    required this.onDiscard,
  });

  final int keeping;
  final int total;
  final VoidCallback? onApply;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return GlassChrome(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(m.spaceMd),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  keeping == 0
                      ? 'Nothing selected'
                      : 'Keeping $keeping of $total '
                          '${total == 1 ? 'section' : 'sections'}',
                  style: context.texts.labelMedium,
                ),
              ),
              TextButton(
                onPressed: onDiscard,
                child: const Text('Discard all'),
              ),
              SizedBox(width: m.spaceSm),
              FilledButton.icon(
                onPressed: onApply == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onApply!();
                      },
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Apply'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
