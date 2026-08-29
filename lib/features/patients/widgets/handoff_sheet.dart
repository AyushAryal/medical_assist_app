import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../clinical/flags/clinical_flag.dart';
import '../../../clinical/summary/handoff.dart';
import '../../../core/app_bootstrap.dart';
import '../../../core/design/design.dart';
import '../../../data/services/assist/language_model.dart';

/// Shows a deterministic SBAR handoff, ready to read aloud or copy.
///
/// The structured SBAR is the source of truth — no editing, so what is copied
/// is exactly what the record says. When an on-device model is available, it
/// can additionally *reword* that same handoff into a natural paragraph for
/// reading aloud; that version is marked as generated and never replaces the
/// structured one. If no model is present, the feature simply is not offered —
/// the handoff works without it.
class HandoffSheet extends StatefulWidget {
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
  State<HandoffSheet> createState() => _HandoffSheetState();
}

class _HandoffSheetState extends State<HandoffSheet> {
  LanguageModelDraft? _spoken;
  bool _busy = false;

  Future<void> _generate() async {
    final bootstrap = context.read<AppBootstrap>();
    var engine = bootstrap.assistEngine;
    if (engine == null || _busy) return;

    setState(() => _busy = true);
    try {
      // Rebuild a not-yet-ready engine (fresh download / stuck load) instead
      // of dead-ending — see AiDraftSheet for the same handling.
      if (!await engine.isReady()) {
        await bootstrap.refreshAssistEngine();
        engine = bootstrap.assistEngine;
        if (engine == null) return;
      }
      final draft = await engine.spokenHandoff(widget.handoff.plainText);
      if (mounted) setState(() => _spoken = draft);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final handoff = widget.handoff;
    final engineAvailable = context.read<AppBootstrap>().assistEngine != null;

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
        if (engineAvailable) _SpokenSection(
          draft: _spoken,
          busy: _busy,
          onGenerate: _generate,
        ),
      ],
    );
  }
}

/// The AI convenience: a reworded, read-aloud version of the same handoff.
class _SpokenSection extends StatelessWidget {
  const _SpokenSection({
    required this.draft,
    required this.busy,
    required this.onGenerate,
  });

  final LanguageModelDraft? draft;
  final bool busy;
  final Future<void> Function() onGenerate;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final d = draft;

    if (d == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: busy ? null : () => onGenerate(),
          icon: busy
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(busy ? 'Rewording…' : 'Read-aloud version'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const AiBadge(),
            const Spacer(),
            IconButton(
              tooltip: 'Copy spoken version',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: d.text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Spoken version copied')),
                  );
                }
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
          ],
        ),
        SizedBox(height: m.spaceXs),
        Text(d.text, style: context.texts.bodyMedium),
        SizedBox(height: m.spaceSm),
        Text(
          LanguageModelDraft.provenanceNotice,
          style: context.texts.bodySmall
              ?.copyWith(color: context.palette.onSurfaceMuted),
        ),
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
