import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_bootstrap.dart';
import '../../../core/design/design.dart';
import '../../../data/services/assist/language_model.dart';
import '../../../data/services/speech_out.dart';
import 'speak_button.dart';

/// One input a generated draft was built from — a record section, an
/// attachment, a page. Shown behind the "Sources" button so the output is
/// grounded in what the model was actually given.
///
/// These are known deterministically (the app decides what text to feed the
/// model), so they cannot be hallucinated: they are the real inputs, not
/// citations the model invented. [onOpen] navigates to the source when there is
/// somewhere to go — an attachment, a record.
class AiSource {
  const AiSource({required this.label, this.detail, this.onOpen});

  final String label;
  final String? detail;
  final VoidCallback? onOpen;
}

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
    this.notice,
    this.sources = const <AiSource>[],
  });

  final String title;
  final String? subtitle;

  /// What the draft was built from — shown behind a "Sources" button.
  final List<AiSource> sources;

  /// An extra caution shown under the draft (e.g. "prompts, not advice").
  final String? caveat;

  /// The provenance line under the draft. Task-specific — a note draft, a
  /// message to send, a brief — so each caller says what this text is. Falls
  /// back to a neutral generated-text notice.
  final String? notice;

  /// The rewriting task, given the resolved engine.
  final Future<LanguageModelDraft> Function(LanguageModelEngine engine) generate;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required Future<LanguageModelDraft> Function(LanguageModelEngine) generate,
    String? subtitle,
    String? caveat,
    String? notice,
    List<AiSource> sources = const <AiSource>[],
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiDraftSheet(
        title: title,
        subtitle: subtitle,
        caveat: caveat,
        notice: notice,
        sources: sources,
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

  @override
  void dispose() {
    // Don't keep talking after the sheet is gone.
    SpeechOut.stop();
    super.dispose();
  }

  static void _showSources(BuildContext context, List<AiSource> sources) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.all(context.metrics.spaceLg),
          children: <Widget>[
            Text('Built from', style: context.texts.titleMedium),
            SizedBox(height: context.metrics.spaceXs),
            Text(
              'The record this was generated from. Nothing here is invented — '
              'these are the exact entries the assistant was given.',
              style: context.texts.bodySmall
                  ?.copyWith(color: context.palette.onSurfaceMuted),
            ),
            SizedBox(height: context.metrics.spaceSm),
            for (final source in sources)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(source.label),
                subtitle:
                    source.detail == null ? null : Text(source.detail!),
                trailing: source.onOpen == null
                    ? null
                    : const Icon(Icons.chevron_right),
                onTap: source.onOpen == null
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        source.onOpen!();
                      },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _run() async {
    final bootstrap = context.read<AppBootstrap>();
    var engine = bootstrap.assistEngine;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (engine == null) {
        setState(() => _message = 'No assistant model is installed on this '
            'device yet, so there is nothing to generate. The record works '
            'without it.');
        return;
      }
      // A model that just finished downloading, or an engine that tried to
      // load before the file was complete, reads as "not ready" until it is
      // rebuilt — so rebuild and re-resolve rather than dead-ending the user.
      if (!await engine.isReady()) {
        await bootstrap.refreshAssistEngine();
        engine = bootstrap.assistEngine;
        if (engine == null) {
          setState(() => _message = 'No assistant model is ready yet. It may '
              'still be downloading — try again shortly.');
          return;
        }
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
        if (_busy) ...<Widget>[
          Row(
            children: <Widget>[
              const AiBadge(),
              SizedBox(width: m.spaceSm),
              Text('Generating…',
                  style: context.texts.bodySmall
                      ?.copyWith(color: context.palette.onSurfaceMuted)),
            ],
          ),
          SizedBox(height: m.spaceMd),
          const AiTextPlaceholder(lines: 4),
          SizedBox(height: m.spaceSm),
          Text(
            'The first run loads the model and can take a few seconds.',
            style: context.texts.bodySmall
                ?.copyWith(color: context.palette.onSurfaceMuted),
          ),
        ] else if (_message != null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: m.spaceMd),
            child: Text(_message!, style: context.texts.bodyMedium),
          )
        else if (draft != null) ...<Widget>[
          Row(
            children: <Widget>[
              const AiBadge(),
              const Spacer(),
              SpeakButton(text: draft.text),
            ],
          ),
          SizedBox(height: m.spaceSm),
          // Rendered as Markdown so a generated table shows as a table; plain
          // prose renders as plain text.
          MarkdownView(data: draft.text),
          if (widget.sources.isNotEmpty) ...<Widget>[
            SizedBox(height: m.spaceSm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showSources(context, widget.sources),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: Text('Sources (${widget.sources.length})'),
              ),
            ),
          ],
          if (widget.caveat != null) ...<Widget>[
            SizedBox(height: m.spaceSm),
            Text(widget.caveat!,
                style: context.texts.bodySmall?.copyWith(
                    color: context.palette.caution,
                    fontWeight: FontWeight.w600)),
          ],
          SizedBox(height: m.spaceSm),
          Text(
            widget.notice ?? LanguageModelDraft.generatedNotice,
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
