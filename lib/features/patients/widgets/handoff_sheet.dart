import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../clinical/flags/clinical_flag.dart';
import '../../../clinical/summary/handoff.dart';
import '../../../core/design/design.dart';

/// Shows a deterministic SBAR handoff, ready to read aloud or copy.
///
/// The content is the [Handoff] the chart built — no editing, no free text —
/// so what is copied is exactly what the record says, gaps and all.
class HandoffSheet extends StatelessWidget {
  const HandoffSheet({super.key, required this.handoff});

  final Handoff handoff;

  static Future<void> show(BuildContext context, Handoff handoff) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HandoffSheet(handoff: handoff),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    return SheetScaffold(
      title: 'SBAR handoff',
      subtitle: handoff.identityLine,
      footer: FilledButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: handoff.plainText));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Handoff copied')),
            );
            Navigator.of(context).pop();
          }
        },
        icon: const Icon(Icons.copy_all_outlined),
        label: const Text('Copy handoff'),
      ),
      children: <Widget>[
        for (final section in handoff.sections) ...<Widget>[
          _PartHeader(part: section.part),
          for (final line in section.lines) _LineRow(line: line),
          SizedBox(height: m.spaceMd),
        ],
      ],
    );
  }
}

class _PartHeader extends StatelessWidget {
  const _PartHeader({required this.part});

  final SbarPart part;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceXs),
      child: Row(
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.palette.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              part.letter,
              style: context.texts.labelSmall
                  ?.copyWith(color: context.palette.onPrimary),
            ),
          ),
          SizedBox(width: m.spaceSm),
          Text(part.title, style: context.texts.titleSmall),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final HandoffLine line;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final color = switch (line.severity) {
      FlagSeverity.critical => palette.critical,
      FlagSeverity.caution => palette.caution,
      FlagSeverity.info => palette.info,
      null => line.isRecorded ? palette.onSurface : palette.onSurfaceMuted,
    };

    return Padding(
      padding: EdgeInsets.only(left: m.spaceLg, bottom: m.spaceXs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('•  ', style: context.texts.bodySmall?.copyWith(color: color)),
          Expanded(
            child: Text(
              line.text,
              style: context.texts.bodySmall?.copyWith(
                color: color,
                fontStyle:
                    line.isRecorded ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
