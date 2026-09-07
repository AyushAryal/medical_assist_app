import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../data/models/clinical_note.dart';
import 'note_templates.dart';

/// Which sections a template may write into.
class TemplateApplication {
  const TemplateApplication({
    required this.template,
    required this.sections,
  });

  final NoteTemplate template;

  /// Section key to whether the template's text should be written there.
  final Map<String, bool> sections;

  bool writesTo(String section) => sections[section] ?? false;
}

/// One SOAP section as the picker sees it: what is there now, and what the
/// template would put there.
typedef TemplateSection = ({String key, String label, String current});

/// Chooses a note template, showing what it will do before it does it.
///
/// The behaviour this replaces silently skipped any section that already had
/// text. That is the safe rule, and as an *invisible* rule it is worse than
/// unsafe: a clinician who has written two lines of history picks a template,
/// sees three of four sections fill, and cannot tell whether the fourth failed,
/// was empty in the template, or was deliberately protected. So the conflict is
/// now the main thing the sheet shows, the default is still to protect written
/// text, and overwriting is available but must be chosen per section.
class TemplatePickerSheet extends StatefulWidget {
  const TemplatePickerSheet({super.key, required this.sections});

  final List<TemplateSection> sections;

  static Future<TemplateApplication?> show(
    BuildContext context, {
    required List<TemplateSection> sections,
  }) {
    return showModalBottomSheet<TemplateApplication>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => TemplatePickerSheet(sections: sections),
    );
  }

  @override
  State<TemplatePickerSheet> createState() => _TemplatePickerSheetState();
}

class _TemplatePickerSheetState extends State<TemplatePickerSheet> {
  NoteTemplate? _chosen;
  late Map<String, bool> _write;

  String _templateText(NoteTemplate template, String key) => switch (key) {
        'subjective' => template.subjective,
        'objective' => template.objective,
        'assessment' => template.assessment,
        _ => template.plan,
      };

  void _choose(NoteTemplate template) {
    setState(() {
      _chosen = template;
      // Default: fill what is empty, protect what is written. The clinician
      // can change any of these, but never by accident.
      _write = <String, bool>{
        for (final section in widget.sections)
          section.key: _templateText(template, section.key).trim().isNotEmpty &&
              section.current.trim().isEmpty,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          maxWidth: m.contentMaxWidth,
        ),
        child: _chosen == null ? _chooser(context) : _preview(context),
      ),
    );
  }

  Widget _chooser(BuildContext context) {
    final m = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceSm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Insert a template', style: context.texts.titleLarge),
              SizedBox(height: m.spaceXs),
              Text(
                'Prompts for the sections, so nothing is forgotten under time '
                'pressure. You will see what it changes before it changes it.',
                style: context.texts.bodySmall,
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(m.spaceLg, m.spaceSm, m.spaceLg, m.spaceLg),
            itemCount: NoteTemplates.all.length,
            separatorBuilder: (_, _) => SizedBox(height: m.spaceSm),
            itemBuilder: (context, index) {
              final template = NoteTemplates.all[index];
              final fills = widget.sections
                  .where((s) => _templateText(template, s.key).trim().isNotEmpty)
                  .map((s) => s.label)
                  .toList();

              return GlassPanel(
                onTap: () => _choose(template),
                padding: EdgeInsets.all(m.spaceMd),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(template.name, style: context.texts.titleSmall),
                          SizedBox(height: m.spaceXs / 2),
                          Text(
                            fills.isEmpty
                                ? 'Empty — clears nothing, adds nothing'
                                : 'Fills ${fills.join(', ')}',
                            style: context.texts.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      label: template.noteType.label,
                      tone: PillTone.neutral,
                      dense: true,
                    ),
                    SizedBox(width: m.spaceSm),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _preview(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final template = _chosen!;

    final relevant = widget.sections
        .where((s) => _templateText(template, s.key).trim().isNotEmpty)
        .toList();
    final conflicts =
        relevant.where((s) => s.current.trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceSm),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Back to templates',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _chosen = null),
              ),
              Expanded(
                child: Text(template.name, style: context.texts.titleLarge),
              ),
            ],
          ),
        ),
        if (conflicts.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceMd),
            child: Callout(
              title: conflicts.length == 1
                  ? '1 section already has text'
                  : '${conflicts.length} sections already have text',
              icon: Icons.edit_note,
              tone: palette.caution,
              subtitle: 'Your writing is kept unless you say otherwise.',
              child: const SizedBox.shrink(),
            ),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceMd),
            children: <Widget>[
              if (relevant.isEmpty)
                const EmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'This template adds nothing',
                  message: 'It sets the note type and leaves your text alone.',
                  compact: true,
                ),
              for (final section in relevant)
                Padding(
                  padding: EdgeInsets.only(bottom: m.spaceSm),
                  child: _SectionDecision(
                    label: section.label,
                    current: section.current,
                    proposed: _templateText(template, section.key),
                    useTemplate: _write[section.key] ?? false,
                    onChanged: (value) =>
                        setState(() => _write[section.key] = value),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceLg),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              SizedBox(width: m.spaceSm),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    TemplateApplication(template: template, sections: _write),
                  ),
                  child: Text(
                    _write.values.any((v) => v)
                        ? 'Insert into '
                            '${_write.values.where((v) => v).length} section'
                            '${_write.values.where((v) => v).length == 1 ? '' : 's'}'
                        : 'Set note type only',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One section's before/after, with the choice attached to it.
class _SectionDecision extends StatelessWidget {
  const _SectionDecision({
    required this.label,
    required this.current,
    required this.proposed,
    required this.useTemplate,
    required this.onChanged,
  });

  final String label;
  final String current;
  final String proposed;
  final bool useTemplate;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final hasText = current.trim().isNotEmpty;

    return GlassPanel(
      padding: EdgeInsets.all(m.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(label, style: context.texts.titleSmall),
              ),
              if (hasText)
                StatusPill(
                  label: useTemplate ? 'Will be replaced' : 'Keeping yours',
                  tone: useTemplate ? PillTone.critical : PillTone.normal,
                  dense: true,
                )
              else
                Switch.adaptive(value: useTemplate, onChanged: onChanged),
            ],
          ),
          if (hasText) ...<Widget>[
            SizedBox(height: m.spaceSm),
            _Excerpt(
              caption: 'What you wrote',
              text: current,
              tone: palette.normal,
            ),
            SizedBox(height: m.spaceSm),
            _Excerpt(
              caption: 'What the template would put here',
              text: proposed,
              tone: palette.onSurfaceMuted,
            ),
            SizedBox(height: m.spaceSm),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Keep mine'),
                  icon: Icon(Icons.lock_outline, size: 16),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Replace'),
                  icon: Icon(Icons.swap_horiz, size: 16),
                ),
              ],
              selected: <bool>{useTemplate},
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ] else ...<Widget>[
            SizedBox(height: m.spaceXs),
            _Excerpt(
              caption: 'Empty — the template will fill it',
              text: proposed,
              tone: palette.onSurfaceMuted,
            ),
          ],
        ],
      ),
    );
  }
}

class _Excerpt extends StatelessWidget {
  const _Excerpt({
    required this.caption,
    required this.text,
    required this.tone,
  });

  final String caption;
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          caption,
          style: context.texts.labelSmall?.copyWith(color: tone),
        ),
        SizedBox(height: m.spaceXs / 2),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(m.spaceSm),
          decoration: BoxDecoration(
            color: palette.surfaceMuted,
            borderRadius: BorderRadius.circular(m.radiusXs),
          ),
          child: Text(
            text.trim(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodySmall,
          ),
        ),
      ],
    );
  }
}
