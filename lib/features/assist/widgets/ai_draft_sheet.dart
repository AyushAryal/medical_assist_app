import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_bootstrap.dart';
import '../../../core/design/design.dart';
import '../../../data/services/assist/language_model.dart';

/// A reusable sheet for a single generated draft.
///
/// One place for the whole "the model rewrote something" pattern: it fetches
/// the on-device engine, runs the caller's rewriting task, and shows the result
/// under an [AiBadge] with the standard provenance notice and a copy action.
/// The caller owns the *task* (which structured text, which prompt); the sheet
/// owns the safety envelope, so no feature reimplements it. If no model is
/// installed it says so and offers nothing — nothing here is ever load-bearing.
class AiDraftSheet extends StatefulWidget {
  const AiDraftSheet({
    super.key,
    required this.title,
    required this.generate,
    this.subtitle,
    this.caveat,
  });

  final String title;
  final String? subtitle;

  /// An extra caution shown under the draft (e.g. "prompts, not advice").
  final String? caveat;

  /// The rewriting task, given the resolved engine.
  final Future<LanguageModelDraft> Function(LanguageModelEngine engine) generate;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required Future<LanguageModelDraft> Function(LanguageModelEngine) generate,
    String? subtitle,
    String? caveat,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiDraftSheet(
        title: title,
        subtitle: subtitle,
        caveat: caveat,
        generate: generate,
      ),
    );
  }

  @override
  State<AiDraftSheet> createState() => _AiDraftSheetState();
}

class _AiDraftSheetState extends State<AiDraftSheet> {
  bool _started = false;
  bool _busy = false;
  String? _message;
  LanguageModelDraft? _draft;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _run();
  }

  Future<void> _run() async {
    final engine = context.read<AppBootstrap>().assistEngine;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (engine == null) {
        setState(() => _message = 'No assistant model is installed on this '
            'device, so there is nothing to generate. The record works without '
            'it.');
        return;
      }
      if (!await engine.isReady()) {
        setState(() => _message = 'The assistant model is still loading. Try '
            'again in a moment.');
        return;
      }
      final draft = await widget.generate(engine);
      if (mounted) setState(() => _draft = draft);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final draft = _draft;

    return SheetScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      footer: draft == null
          ? null
          : FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: draft.text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')),
                  );
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Copy'),
            ),
      children: <Widget>[
        if (_busy)
          Padding(
            padding: EdgeInsets.symmetric(vertical: m.spaceLg),
            child: Row(
              children: <Widget>[
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: m.spaceSm),
                Text('Generating…', style: context.texts.bodySmall),
              ],
            ),
          )
        else if (_message != null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: m.spaceMd),
            child: Text(_message!, style: context.texts.bodyMedium),
          )
        else if (draft != null) ...<Widget>[
          Row(children: const <Widget>[AiBadge()]),
          SizedBox(height: m.spaceSm),
          Text(draft.text, style: context.texts.bodyMedium),
          if (widget.caveat != null) ...<Widget>[
            SizedBox(height: m.spaceSm),
            Text(widget.caveat!,
                style: context.texts.bodySmall?.copyWith(
                    color: context.palette.caution,
                    fontWeight: FontWeight.w600)),
          ],
          SizedBox(height: m.spaceSm),
          Text(
            LanguageModelDraft.provenanceNotice,
            style: context.texts.bodySmall
                ?.copyWith(color: context.palette.onSurfaceMuted),
          ),
          SizedBox(height: m.spaceSm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _run,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Regenerate'),
            ),
          ),
        ],
      ],
    );
  }
}
