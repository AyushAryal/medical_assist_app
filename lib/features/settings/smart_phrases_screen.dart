import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';
import '../../core/utils/ids.dart';
import '../../data/models/smart_phrase_record.dart';
import '../../data/repositories/clinical_repository.dart';

/// Manage the clinic's text-expansion smart phrases.
///
/// The dynamic macros (`\pat`, `\me`, `\today`, `\clinic`) are not shown here —
/// they are behaviour, not text, and live in code. What a clinician edits here
/// is their own vocabulary of expansions: type `\ros` in a note and out comes a
/// review-of-systems template they wrote once. This screen doubles as the guide,
/// because the fastest way to teach the feature is to show the phrases that
/// already exist and let one be edited.
class SmartPhrasesScreen extends StatefulWidget {
  const SmartPhrasesScreen({super.key});

  @override
  State<SmartPhrasesScreen> createState() => _SmartPhrasesScreenState();
}

class _SmartPhrasesScreenState extends State<SmartPhrasesScreen> {
  List<SmartPhraseRecord> _phrases = const <SmartPhraseRecord>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final records =
        await context.read<ClinicalRepository>().smartPhrases.all();
    if (!mounted) return;
    setState(() {
      _phrases = records;
      _loading = false;
    });
  }

  Future<void> _edit([SmartPhraseRecord? existing]) async {
    final saved = await _SmartPhraseEditor.show(context, existing);
    if (saved == null || !mounted) return;
    await context.read<ClinicalRepository>().smartPhrases.upsert(saved);
    await _load();
  }

  Future<void> _delete(SmartPhraseRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove \\${record.trigger}?'),
        content: const Text('This removes the phrase from every field.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<ClinicalRepository>().smartPhrases.archive(record.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Smart phrases'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add a phrase',
            icon: const Icon(Icons.add),
            onPressed: () => _edit(),
          ),
        ],
      ),
      body: ContentWidth(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: pagePadding(context, floatingBar: false),
                children: <Widget>[
                  SectionCard(
                    title: 'Type \\ to summon a phrase',
                    leading: Icon(Icons.bolt_outlined,
                        size: 20, color: context.palette.accent),
                    child: Text(
                      'In the assistant, and anywhere you see the spark, type a '
                      'backslash to open this list. Text phrases below expand in '
                      'place. Built-in macros — \\pat (pick a patient), \\me, '
                      '\\today, \\clinic — resolve automatically and are not '
                      'edited here.',
                      style: context.texts.bodySmall,
                    ),
                  ),
                  SizedBox(height: m.spaceMd),
                  for (final phrase in _phrases) ...<Widget>[
                    _PhraseTile(
                      phrase: phrase,
                      onEdit: () => _edit(phrase),
                      onDelete: () => _delete(phrase),
                    ),
                    SizedBox(height: m.spaceSm),
                  ],
                  if (_phrases.isEmpty)
                    const EmptyState(
                      icon: Icons.bolt_outlined,
                      title: 'No phrases yet',
                      message: 'Add one with the + button.',
                    ),
                ],
              ),
      ),
    );
  }
}

class _PhraseTile extends StatelessWidget {
  const _PhraseTile({
    required this.phrase,
    required this.onEdit,
    required this.onDelete,
  });

  final SmartPhraseRecord phrase;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SectionCard(
      title: '\\${phrase.trigger}  ·  ${phrase.title}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline, size: 20),
            color: palette.critical,
            onPressed: onDelete,
          ),
        ],
      ),
      child: Text(phrase.body, style: context.texts.bodySmall),
    );
  }
}

/// Add or edit a single phrase.
class _SmartPhraseEditor extends StatefulWidget {
  const _SmartPhraseEditor({this.existing});

  final SmartPhraseRecord? existing;

  static Future<SmartPhraseRecord?> show(
    BuildContext context,
    SmartPhraseRecord? existing,
  ) {
    return showModalBottomSheet<SmartPhraseRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _SmartPhraseEditor(existing: existing),
      ),
    );
  }

  @override
  State<_SmartPhraseEditor> createState() => _SmartPhraseEditorState();
}

class _SmartPhraseEditorState extends State<_SmartPhraseEditor> {
  late final TextEditingController _trigger =
      TextEditingController(text: widget.existing?.trigger ?? '');
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.existing?.body ?? '');
  String? _error;

  @override
  void dispose() {
    _trigger.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _save() {
    final trigger = _trigger.text.trim().toLowerCase().replaceAll(' ', '');
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (trigger.isEmpty || title.isEmpty || body.isEmpty) {
      setState(() => _error = 'A trigger, a title and the text are all needed.');
      return;
    }

    final now = DateTime.now();
    final existing = widget.existing;
    final record = existing == null
        ? SmartPhraseRecord(
            id: newId(),
            trigger: trigger,
            title: title,
            body: body,
            createdAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            trigger: trigger,
            title: title,
            body: body,
            updatedAt: now,
            revision: existing.revision + 1,
            syncStatus: 'pending',
          );
    Navigator.of(context).pop(record);
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
            Text(
              widget.existing == null ? 'New phrase' : 'Edit phrase',
              style: context.texts.titleMedium,
            ),
            SizedBox(height: m.spaceMd),
            LabeledField(
              label: 'Trigger',
              controller: _trigger,
              hint: 'ros',
              helper: 'Typed after the backslash, no spaces.',
            ),
            SizedBox(height: m.spaceSm),
            LabeledField(
              label: 'Title',
              controller: _title,
              hint: 'Review of systems',
            ),
            SizedBox(height: m.spaceSm),
            LabeledField(
              label: 'Expands to',
              controller: _body,
              hint: 'The text this phrase inserts…',
              maxLines: 5,
            ),
            if (_error case final error?) ...<Widget>[
              SizedBox(height: m.spaceSm),
              Text(
                error,
                style: context.texts.bodySmall
                    ?.copyWith(color: context.palette.critical),
              ),
            ],
            SizedBox(height: m.spaceMd),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
