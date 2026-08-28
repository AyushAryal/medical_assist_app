import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/utils/ids.dart';
import '../../data/models/allergy.dart';
import '../../data/models/medication.dart';
import '../../data/models/problem.dart';
import 'patient_chart_controller.dart';

/// Bottom sheets for adding to the three chart lists.
///
/// Sheets rather than full screens on purpose: adding a problem happens *while*
/// reading the chart, and pushing a route loses the reading position the
/// clinician was in.

class AllergySheet extends StatefulWidget {
  const AllergySheet({super.key});

  static Future<void> show(
    BuildContext context,
    PatientChartController chart,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<PatientChartController>.value(
        value: chart,
        child: const AllergySheet(),
      ),
    );
  }

  @override
  State<AllergySheet> createState() => _AllergySheetState();
}

class _AllergySheetState extends State<AllergySheet> {
  final TextEditingController _substance = TextEditingController();
  final TextEditingController _reaction = TextEditingController();
  AllergyCategory _category = AllergyCategory.drug;
  AllergySeverity _severity = AllergySeverity.unknown;
  bool _busy = false;

  @override
  void dispose() {
    _substance.dispose();
    _reaction.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_substance.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);

    final chart = context.read<PatientChartController>();
    final now = DateTime.now();
    await chart.addAllergy(
      Allergy(
        id: newId(),
        patientId: chart.patientId,
        substance: _substance.text.trim(),
        category: _category,
        reaction: _reaction.text.trim().isEmpty ? null : _reaction.text.trim(),
        severity: _severity,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SheetScaffold(
      title: 'Add allergy',
      onSave: _busy ? null : _save,
      children: <Widget>[
        LabeledField(
          label: 'Substance',
          controller: _substance,
          autofocus: true,
          hint: 'e.g. Penicillin',
        ),
        SizedBox(height: m.spaceMd),
        LabeledField(
          label: 'Reaction',
          controller: _reaction,
          hint: 'e.g. Urticaria, airway swelling',
        ),
        SizedBox(height: m.spaceLg),
        ChoiceChipRow<AllergyCategory>(
          label: 'Category',
          values: AllergyCategory.values,
          labelOf: (c) => c.label,
          selected: _category,
          onSelected: (c) => setState(() => _category = c ?? _category),
        ),
        SizedBox(height: m.spaceLg),
        ChoiceChipRow<AllergySeverity>(
          label: 'Severity',
          values: AllergySeverity.values,
          labelOf: (s) => s.label,
          selected: _severity,
          onSelected: (s) => setState(() => _severity = s ?? _severity),
        ),
        SizedBox(height: m.spaceXs),
        Text(
          'Severe and anaphylactic reactions are shown as a red banner on '
          'every screen for this patient.',
          style: context.texts.labelSmall,
        ),
      ],
    );
  }
}

class ProblemSheet extends StatefulWidget {
  const ProblemSheet({super.key});

  static Future<void> show(
    BuildContext context,
    PatientChartController chart,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<PatientChartController>.value(
        value: chart,
        child: const ProblemSheet(),
      ),
    );
  }

  @override
  State<ProblemSheet> createState() => _ProblemSheetState();
}

class _ProblemSheetState extends State<ProblemSheet> {
  final TextEditingController _display = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _isChronic = false;
  bool _busy = false;

  @override
  void dispose() {
    _display.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_display.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);

    final chart = context.read<PatientChartController>();
    final now = DateTime.now();
    await chart.addProblem(
      Problem(
        id: newId(),
        patientId: chart.patientId,
        display: _display.text.trim(),
        codeSystem: _code.text.trim().isEmpty ? null : 'ICD-10',
        code: _code.text.trim().isEmpty ? null : _code.text.trim(),
        isChronic: _isChronic,
        onsetDate: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SheetScaffold(
      title: 'Add problem',
      onSave: _busy ? null : _save,
      children: <Widget>[
        LabeledField(
          label: 'Diagnosis',
          controller: _display,
          autofocus: true,
          hint: 'e.g. Type 2 diabetes mellitus',
        ),
        SizedBox(height: m.spaceMd),
        LabeledField(
          label: 'ICD-10 code (optional)',
          controller: _code,
          hint: 'e.g. E11.9',
          textCapitalization: TextCapitalization.characters,
        ),
        SizedBox(height: m.spaceMd),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _isChronic,
          onChanged: (value) => setState(() => _isChronic = value),
          title: const Text('Chronic condition'),
          subtitle: const Text('Kept at the top of the problem list'),
        ),
      ],
    );
  }
}

class MedicationSheet extends StatefulWidget {
  const MedicationSheet({super.key});

  static Future<void> show(
    BuildContext context,
    PatientChartController chart,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<PatientChartController>.value(
        value: chart,
        child: const MedicationSheet(),
      ),
    );
  }

  @override
  State<MedicationSheet> createState() => _MedicationSheetState();
}

class _MedicationSheetState extends State<MedicationSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _dose = TextEditingController();
  final TextEditingController _indication = TextEditingController();
  String? _route = 'PO';
  String? _frequency = 'OD';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _indication.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);

    final chart = context.read<PatientChartController>();
    final now = DateTime.now();
    await chart.addMedication(
      Medication(
        id: newId(),
        patientId: chart.patientId,
        name: _name.text.trim(),
        dose: _dose.text.trim().isEmpty ? null : _dose.text.trim(),
        route: _route,
        frequency: _frequency,
        indication:
            _indication.text.trim().isEmpty ? null : _indication.text.trim(),
        startedOn: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SheetScaffold(
      title: 'Add medication',
      onSave: _busy ? null : _save,
      children: <Widget>[
        LabeledField(
          label: 'Medication',
          controller: _name,
          autofocus: true,
          hint: 'e.g. Amoxicillin',
        ),
        SizedBox(height: m.spaceMd),
        LabeledField(
          label: 'Dose',
          controller: _dose,
          hint: 'e.g. 500 mg',
        ),
        SizedBox(height: m.spaceLg),
        ChoiceChipRow<String>(
          label: 'Route',
          values: MedicationRoutes.common,
          labelOf: (r) => r,
          selected: _route,
          onSelected: (r) => setState(() => _route = r ?? _route),
        ),
        SizedBox(height: m.spaceLg),
        ChoiceChipRow<String>(
          label: 'Frequency',
          values: MedicationFrequencies.common,
          labelOf: (f) => f,
          selected: _frequency,
          onSelected: (f) => setState(() => _frequency = f ?? _frequency),
        ),
        SizedBox(height: m.spaceLg),
        LabeledField(
          label: 'Indication (optional)',
          controller: _indication,
        ),
      ],
    );
  }
}

