import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../clinical/insights/note_intelligence.dart';
import '../../core/design/design.dart';
import '../../core/utils/ids.dart';
import '../../data/models/allergy.dart';
import '../../data/models/medication.dart';
import '../../data/models/problem.dart';
import '../../data/repositories/clinical_repository.dart';
import '../scan/scan.dart';

/// Pull structured entries out of a block of text — a referral letter, old
/// notes, a photo of a page — and file the ones you want.
///
/// Deterministic first: the app's own dictionary finds medicines, diagnoses,
/// allergies and follow-ups, so it works with no model and its behaviour is
/// exactly predictable. **Nothing is filed until you tap it** — every row is a
/// suggestion, matched from your text, that you accept or ignore.
class SmartIntakeScreen extends StatefulWidget {
  const SmartIntakeScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<SmartIntakeScreen> createState() => _SmartIntakeScreenState();
}

class _SmartIntakeScreenState extends State<SmartIntakeScreen> {
  final TextEditingController _input = TextEditingController();
  List<ExtractedTerm> _terms = const <ExtractedTerm>[];
  final Set<String> _filed = <String>{};

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _extract() {
    setState(() {
      _terms = NoteIntelligence.extract(_input.text);
      _filed.clear();
    });
  }

  Future<void> _scan() async {
    final text = await scanTextFrom(context);
    if (text == null || text.trim().isEmpty) return;
    final existing = _input.text.trimRight();
    _input.text = existing.isEmpty ? text : '$existing\n$text';
    _extract();
  }

  Future<void> _file(ExtractedTerm term) async {
    final repo = context.read<ClinicalRepository>();
    final now = DateTime.now();
    final id = newId();
    switch (term.kind) {
      case ExtractedTermKind.allergy:
        await repo.patients.addAllergy(Allergy(
          id: id, patientId: widget.patientId, substance: term.text,
          createdAt: now, updatedAt: now));
      case ExtractedTermKind.problem:
        await repo.patients.addProblem(Problem(
          id: id, patientId: widget.patientId, display: term.text,
          createdAt: now, updatedAt: now));
      case ExtractedTermKind.medication:
        await repo.patients.addMedication(Medication(
          id: id, patientId: widget.patientId, name: term.text,
          createdAt: now, updatedAt: now));
      case ExtractedTermKind.followUp:
      case ExtractedTermKind.redFlag:
        return; // prompts, not list entries
    }
    if (mounted) setState(() => _filed.add(_key(term)));
  }

  static String _key(ExtractedTerm t) => '${t.kind.name}:${t.text}';

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final fileable = _terms
        .where((t) =>
            t.kind == ExtractedTermKind.allergy ||
            t.kind == ExtractedTermKind.problem ||
            t.kind == ExtractedTermKind.medication)
        .toList();
    final flags =
        _terms.where((t) => t.kind == ExtractedTermKind.redFlag).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Smart intake'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Scan a page',
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: _scan,
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.all(m.spaceLg),
          children: <Widget>[
            SectionCard(
              title: 'Paste or scan text',
              subtitle: 'A referral, old notes, a photo of a page',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _input,
                    maxLines: null,
                    minLines: 4,
                    keyboardType: TextInputType.multiline,
                    style: context.texts.bodyMedium,
                    decoration: const InputDecoration(
                      hintText: 'Paste text here, or use the scan button…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: m.spaceSm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _scan,
                          icon: const Icon(Icons.document_scanner_outlined,
                              size: 18),
                          label: const Text('Scan'),
                        ),
                      ),
                      SizedBox(width: m.spaceSm),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _extract,
                          icon: const Icon(Icons.auto_fix_high, size: 18),
                          label: const Text('Find entries'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: m.spaceMd),
            if (_terms.isEmpty)
              const EmptyState(
                icon: Icons.playlist_add_check_outlined,
                title: 'Suggestions appear here',
                message: 'Add some text and tap "Find entries". Nothing is '
                    'filed until you tap Add.',
              )
            else ...<Widget>[
              if (fileable.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: m.spaceSm),
                  child: Text('No medicines, problems or allergies recognised.',
                      style: context.texts.bodySmall),
                )
              else
                SectionCard(
                  title: 'Found ${fileable.length} to review',
                  subtitle: 'Tap Add to file — nothing here is on the chart yet',
                  child: Column(
                    children: <Widget>[
                      for (final term in fileable)
                        _SuggestionRow(
                          term: term,
                          filed: _filed.contains(_key(term)),
                          onAdd: () => _file(term),
                        ),
                    ],
                  ),
                ),
              if (flags.isNotEmpty) ...<Widget>[
                SizedBox(height: m.spaceMd),
                SectionCard(
                  title: 'Red flags in the text',
                  subtitle: 'Prompts to consider — not filed',
                  child: Column(
                    children: <Widget>[
                      for (final f in flags)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: m.spaceXs),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.flag_outlined,
                                  size: 16, color: context.palette.caution),
                              SizedBox(width: m.spaceSm),
                              Expanded(child: Text(f.text)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.term,
    required this.filed,
    required this.onAdd,
  });

  final ExtractedTerm term;
  final bool filed;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: StatusPill(label: term.kind.label, tone: PillTone.info, dense: true),
      title: Text(term.text),
      subtitle: Text('from "${term.matchedPhrase}"',
          style: context.texts.bodySmall),
      trailing: filed
          ? Icon(Icons.check_circle, color: context.palette.normal)
          : FilledButton.tonal(onPressed: onAdd, child: const Text('Add')),
    );
  }
}
