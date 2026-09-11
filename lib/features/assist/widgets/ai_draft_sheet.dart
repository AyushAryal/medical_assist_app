import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_bootstrap.dart';
import '../../../core/design/design.dart';
import '../../../core/smart_phrases/smart_phrase.dart';
import '../../../core/smart_phrases/smart_phrase_field.dart';
import '../../../core/smart_phrases/smart_phrase_library.dart';
import '../../../data/repositories/clinical_repository.dart';
import '../../../data/services/assist/language_model.dart';
import '../../../data/services/letter_pdf.dart';
import '../../../data/services/speech_out.dart';
import 'letter_preview_screen.dart';
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
    this.editable = false,
    this.patientId,
    this.letter,
  });

  final String title;
  final String? subtitle;

  /// Lets the clinician correct the draft in place before copying or
  /// exporting it. The edited text is what every action then uses.
  final bool editable;

  /// The patient the draft is about, so `\`-macros that read the chart
  /// (`\vitals`, `\meds`, …) resolve against the right record while editing.
  final String? patientId;

  /// When set, the footer offers a PDF of the (possibly edited) draft laid on
  /// this letterhead — previewable, printable, shareable (which is also how
  /// it is emailed: the share sheet attaches the PDF to a new message).
  final LetterPdf? letter;

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
    bool editable = false,
    String? patientId,
    LetterPdf? letter,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AiDraftSheet(
        title: title,
        subtitle: subtitle,
        caveat: caveat,
        notice: notice,
        sources: sources,
        editable: editable,
        patientId: patientId,
        letter: letter,
        generate: generate,
      ),
    );
  }

  @override
  State<AiDraftSheet> createState() => _AiDraftSheetState();
}

/// Formatting controls for the draft editor.
///
/// They operate on the Markdown source — bold and italic wrap the selection,
/// heading and bullet prefix the current line — so the "rich text" the
/// clinician sees in the preview is exactly what the PDF prints and Copy
/// carries; there is no second format to drift.
class _FormatBar extends StatelessWidget {
  const _FormatBar({required this.controller});

  final TextEditingController controller;

  void _wrap(String mark) {
    final value = controller.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    final text = value.text;
    final selected = selection.textInside(text);
    final replaced = '$mark$selected$mark';
    controller.value = value.copyWith(
      text: selection.textBefore(text) + replaced + selection.textAfter(text),
      selection: selected.isEmpty
          // Nothing selected: park the caret between the marks, ready to type.
          ? TextSelection.collapsed(offset: selection.start + mark.length)
          : TextSelection(
              baseOffset: selection.start,
              extentOffset: selection.start + replaced.length,
            ),
    );
  }

  void _prefixLine(String prefix) {
    final value = controller.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    final text = value.text;
    final lineStart = text.lastIndexOf('\n', selection.start - 1) + 1;
    final already = text.startsWith(prefix, lineStart);
    final updated = already
        ? text.replaceRange(lineStart, lineStart + prefix.length, '')
        : text.replaceRange(lineStart, lineStart, prefix);
    final shift = already ? -prefix.length : prefix.length;
    controller.value = value.copyWith(
      text: updated,
      selection: TextSelection.collapsed(offset: selection.start + shift),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    Widget action(IconData icon, String tooltip, VoidCallback onTap) =>
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          tooltip: tooltip,
          icon: Icon(icon),
          onPressed: onTap,
        );

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      child: Row(
        children: <Widget>[
          action(Icons.format_bold, 'Bold', () => _wrap('**')),
          action(Icons.format_italic, 'Italic', () => _wrap('*')),
          action(Icons.title, 'Heading', () => _prefixLine('## ')),
          action(
            Icons.format_list_bulleted,
            'Bullet list',
            () => _prefixLine('- '),
          ),
        ],
      ),
    );
  }
}

/// Who the letter is addressed to — one glanceable row with an edit
/// affordance, instead of burying the recipient inside the prose where the
/// model could touch it.
class _RecipientRow extends StatelessWidget {
  const _RecipientRow({required this.recipient, required this.onEdit});

  final LetterRecipient? recipient;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final r = recipient;

    return Material(
      color: palette.surfaceMuted,
      borderRadius: BorderRadius.circular(m.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: m.spaceMd,
            vertical: m.spaceSm,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.outgoing_mail,
                size: 18,
                color: palette.onSurfaceMuted,
              ),
              SizedBox(width: m.spaceSm),
              Expanded(
                child: r == null
                    ? Text(
                        'To: not set — addressed "Dear colleague"',
                        style: context.texts.bodySmall
                            ?.copyWith(color: palette.onSurfaceMuted),
                      )
                    : Text(
                        'To: ${r.name}'
                        '${r.clinic == null ? '' : ' · ${r.clinic}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall,
                      ),
              ),
              Icon(
                r == null ? Icons.add : Icons.edit_outlined,
                size: 16,
                color: palette.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Structured entry for the referred-to clinician. Returned to the sheet,
/// which threads it into the salutation and the letterhead addressee block.
class _RecipientSheet extends StatefulWidget {
  const _RecipientSheet({this.current});

  final LetterRecipient? current;

  static Future<LetterRecipient?> show(
    BuildContext context, {
    LetterRecipient? current,
  }) {
    return showModalBottomSheet<LetterRecipient>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecipientSheet(current: current),
    );
  }

  @override
  State<_RecipientSheet> createState() => _RecipientSheetState();
}

class _RecipientSheetState extends State<_RecipientSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.current?.name ?? '');
  late final TextEditingController _specialty =
      TextEditingController(text: widget.current?.specialty ?? '');
  late final TextEditingController _clinic =
      TextEditingController(text: widget.current?.clinic ?? '');

  @override
  void dispose() {
    _name.dispose();
    _specialty.dispose();
    _clinic.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      LetterRecipient(
        name: name,
        specialty:
            _specialty.text.trim().isEmpty ? null : _specialty.text.trim(),
        clinic: _clinic.text.trim().isEmpty ? null : _clinic.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SheetScaffold(
      title: 'Referred to',
      subtitle: 'Addresses the letter — the draft text is not changed',
      onSave: _save,
      saveLabel: 'Use',
      children: <Widget>[
        LabeledField(
          label: 'Name',
          controller: _name,
          autofocus: true,
          hint: 'e.g. Dr S. Sharma',
          textCapitalization: TextCapitalization.words,
        ),
        SizedBox(height: m.spaceMd),
        LabeledField(
          label: 'Specialty or department',
          controller: _specialty,
          hint: 'e.g. Cardiology',
          textCapitalization: TextCapitalization.words,
        ),
        SizedBox(height: m.spaceMd),
        LabeledField(
          label: 'Clinic or hospital',
          controller: _clinic,
          hint: 'e.g. Patan Hospital',
          textCapitalization: TextCapitalization.words,
        ),
      ],
    );
  }
}

/// Compact provenance affordance in the draft panel's header — quiet enough
/// not to compete with the badge, present enough to be found.
class _SourcesButton extends StatelessWidget {
  const _SourcesButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Material(
      color: palette.surfaceMuted,
      borderRadius: BorderRadius.circular(m.radiusLg * 2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: m.spaceSm + 2,
            vertical: m.spaceXs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.fact_check_outlined,
                size: 14,
                color: palette.onSurfaceMuted,
              ),
              SizedBox(width: m.spaceXs),
              Text(
                'Sources · $count',
                style: context.texts.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiDraftSheetState extends State<AiDraftSheet> {
  bool _started = false;
  bool _busy = false;
  bool _editing = false;
  String? _message;
  LetterRecipient? _recipient;
  LanguageModelDraft? _draft;
  final SmartPhraseController _edited = SmartPhraseController();
  final FocusNode _editFocus = FocusNode();
  SmartPhraseRegistry _phrases = buildSmartPhraseRegistry(const []);

  /// What every action (copy, speak, PDF) operates on: the clinician's edited
  /// text once they have touched it, the generated draft until then.
  String get _text => _edited.text;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _run();
    _loadPhrases();
  }

  @override
  void dispose() {
    // Don't keep talking after the sheet is gone.
    SpeechOut.stop();
    _edited.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  static void _showSources(BuildContext context, List<AiSource> sources) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
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

  /// Custom expansions from Settings; the built-in macros work regardless.
  Future<void> _loadPhrases() async {
    try {
      final records =
          await context.read<ClinicalRepository>().smartPhrases.all();
      if (mounted) setState(() => _phrases = buildSmartPhraseRegistry(records));
    } on Object {
      // Built-ins only.
    }
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
      if (mounted) {
        setState(() {
          _draft = draft;
          _edited.text = draft.text;
          _editing = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final draft = _draft;

    final palette = context.palette;

    return SheetScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      // One primary action and one secondary, side by side — everything else
      // lives with the content it describes.
      footer: draft == null
          ? null
          // Quiet by design: a generated draft's actions should read as
          // offers, not as the loudest thing on the sheet.
          : Row(
              children: <Widget>[
                IconButton(
                  onPressed: _busy ? null : _run,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Regenerate',
                  icon: const Icon(Icons.refresh, size: 20),
                ),
                const Spacer(),
                if (widget.letter != null) ...<Widget>[
                  FilledButton.tonalIcon(
                    onPressed: () => LetterPreviewScreen.open(
                      context,
                      title: widget.title,
                      build: () =>
                          widget.letter!.render(_text, recipient: _recipient),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                    label: const Text('Preview'),
                  ),
                  SizedBox(width: m.spaceSm),
                ],
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied')),
                      );
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.copy_all_outlined, size: 17),
                  label: const Text('Copy'),
                ),
              ],
            ),
      children: <Widget>[
        if (_busy)
          // The same framed panel the finished draft arrives in, so the sheet
          // does not reflow when the text lands.
          GlassPanel(
            padding: EdgeInsets.all(m.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Row(children: <Widget>[AiBadge(label: 'Generating…')]),
                SizedBox(height: m.spaceMd),
                const AiTextPlaceholder(lines: 4),
                SizedBox(height: m.spaceSm),
                Text(
                  'The first run loads the model and can take a few seconds.',
                  style: context.texts.bodySmall
                      ?.copyWith(color: palette.onSurfaceMuted),
                ),
              ],
            ),
          )
        else if (_message != null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: m.spaceMd),
            child: Text(_message!, style: context.texts.bodyMedium),
          )
        else if (draft != null) ...<Widget>[
          if (widget.letter != null) ...<Widget>[
            _RecipientRow(
              recipient: _recipient,
              onEdit: () async {
                final chosen =
                    await _RecipientSheet.show(context, current: _recipient);
                if (chosen != null) setState(() => _recipient = chosen);
              },
            ),
            SizedBox(height: m.spaceSm),
          ],
          // The draft and everything about its provenance in one frame: the
          // badge names what it is, the sources say what it was built from,
          // the notice under it says what it may be used for. One place to
          // look instead of a page of scattered rows.
          GlassPanel(
            padding: EdgeInsets.all(m.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const AiBadge(),
                    const Spacer(),
                    if (widget.sources.isNotEmpty) ...<Widget>[
                      _SourcesButton(
                        count: widget.sources.length,
                        onTap: () => _showSources(context, widget.sources),
                      ),
                      SizedBox(width: m.spaceXs),
                    ],
                    if (widget.editable)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: _editing ? 'Done' : 'Edit',
                        icon: Icon(
                          _editing ? Icons.check : Icons.edit_outlined,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _editing = !_editing),
                      ),
                    SpeakButton(text: _text),
                  ],
                ),
                SizedBox(height: m.spaceMd),
                if (_editing) ...<Widget>[
                  // Rich-text controls over the Markdown source: the same
                  // formatting renders in the preview, in Copy, and in the
                  // printed letter, because they all read this one text.
                  _FormatBar(controller: _edited),
                  SizedBox(height: m.spaceSm),
                  // The clinician's corrections happen here, in place; copy,
                  // speak and the PDF all follow the edited text. Wrapped in
                  // the smart-phrase mechanism, so \-macros expand here the
                  // same way they do in a note.
                  SmartPhraseField(
                    controller: _edited,
                    focusNode: _editFocus,
                    registry: _phrases,
                    scope: SmartPhraseScope(patientId: widget.patientId),
                    // A tall editor: the default top anchor floats the menu a
                    // paragraph above the caret.
                    anchorToFieldBottom: true,
                    child: TextField(
                      controller: _edited,
                      focusNode: _editFocus,
                      maxLines: null,
                      minLines: 6,
                      autofocus: true,
                      style: context.texts.bodyMedium,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ] else
                  // Rendered as Markdown so a generated table shows as a
                  // table; plain prose renders as plain text.
                  MarkdownView(data: _text),
                SizedBox(height: m.spaceMd),
                Text(
                  widget.notice ?? LanguageModelDraft.generatedNotice,
                  style: context.texts.labelSmall
                      ?.copyWith(color: palette.onSurfaceMuted),
                ),
              ],
            ),
          ),
          if (widget.caveat != null) ...<Widget>[
            SizedBox(height: m.spaceMd),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.error_outline, size: 16, color: palette.caution),
                SizedBox(width: m.spaceSm),
                Expanded(
                  child: Text(
                    widget.caveat!,
                    style: context.texts.bodySmall?.copyWith(
                      color: palette.caution,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
