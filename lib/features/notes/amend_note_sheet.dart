import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/session/session_controller.dart';
import '../../data/models/clinical_note.dart';
import '../../data/repositories/clinical_repository.dart';

/// Adds a correction to a signed note.
///
/// The reason is mandatory. An amendment without a stated reason tells a
/// future reader — or an investigation — that the record changed but not why,
/// which is worse than no amendment at all.
class AmendNoteSheet extends StatefulWidget {
  const AmendNoteSheet({super.key, required this.note});

  final ClinicalNote note;

  static Future<void> show(
    BuildContext context, {
    required ClinicalNote note,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MultiProvider(
        providers: [
          Provider<ClinicalRepository>.value(
            value: context.read<ClinicalRepository>(),
          ),
          ChangeNotifierProvider<SessionController>.value(
            value: context.read<SessionController>(),
          ),
        ],
        child: AmendNoteSheet(note: note),
      ),
    );
  }

  @override
  State<AmendNoteSheet> createState() => _AmendNoteSheetState();
}

class _AmendNoteSheetState extends State<AmendNoteSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _busy = false;

  static const List<String> _commonReasons = <String>[
    'Correction of an error',
    'Additional information available',
    'Result received after signing',
    'Clarification',
  ];

  @override
  void dispose() {
    _reason.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() => _busy = true);

    final repository = context.read<ClinicalRepository>();
    final session = context.read<SessionController>();

    await repository.amendNote(
      note: widget.note,
      body: _body.text.trim(),
      reason: _reason.text.trim(),
      author: session.signatureName,
    );

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: m.spaceLg,
          right: m.spaceLg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + m.spaceLg,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Add amendment', style: context.texts.titleMedium),
                SizedBox(height: m.spaceXs),
                Text(
                  'The signed note stays exactly as it was. This is appended '
                  'below it and both remain part of the record.',
                  style: context.texts.bodySmall,
                ),
                SizedBox(height: m.spaceLg),
                LabeledField(
                  label: 'Reason for amendment',
                  controller: _reason,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'A reason is required'
                      : null,
                ),
                SizedBox(height: m.spaceSm),
                Wrap(
                  spacing: m.spaceSm,
                  runSpacing: m.spaceSm,
                  children: _commonReasons
                      .map(
                        (reason) => ActionChip(
                          label: Text(reason),
                          onPressed: () => _reason.text = reason,
                        ),
                      )
                      .toList(),
                ),
                SizedBox(height: m.spaceLg),
                LabeledField(
                  label: 'Amendment',
                  controller: _body,
                  maxLines: 6,
                  minLines: 3,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter the correction'
                      : null,
                ),
                SizedBox(height: m.spaceXl),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Append amendment'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
