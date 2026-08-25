import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/session/session_controller.dart';
import '../../data/models/encounter.dart';
import '../../data/models/patient.dart';
import '../../data/repositories/clinical_repository.dart';

/// Starting a visit is two decisions — what kind, and why they came — so it is
/// a sheet rather than a screen. Anything else about the encounter can be
/// filled in as the consultation goes on.
class StartEncounterSheet extends StatefulWidget {
  const StartEncounterSheet({super.key, required this.patient});

  final Patient patient;

  static Future<Encounter?> show(
    BuildContext context, {
    required Patient patient,
  }) {
    return showModalBottomSheet<Encounter>(
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
        child: StartEncounterSheet(patient: patient),
      ),
    );
  }

  @override
  State<StartEncounterSheet> createState() => _StartEncounterSheetState();
}

class _StartEncounterSheetState extends State<StartEncounterSheet> {
  final TextEditingController _complaint = TextEditingController();
  EncounterType _type = EncounterType.followUp;
  bool _busy = false;

  /// Presenting complaints seen often enough to be worth a single tap.
  /// Tapping fills the field rather than replacing it, so it stays editable —
  /// the patient's own words matter more than a tidy category.
  static const List<String> _commonComplaints = <String>[
    'Fever',
    'Cough',
    'Headache',
    'Abdominal pain',
    'Chest pain',
    'Shortness of breath',
    'Diarrhoea',
    'Back pain',
    'Injury',
    'Review of results',
  ];

  @override
  void initState() {
    super.initState();
    // A patient with no prior visit is by definition a new-patient encounter.
    _type = widget.patient.lastSeenAt == null
        ? EncounterType.newPatient
        : EncounterType.followUp;
  }

  @override
  void dispose() {
    _complaint.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    final session = context.read<SessionController>();
    final clinic = session.activeClinic;
    if (clinic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a clinic first.')),
      );
      return;
    }

    setState(() => _busy = true);
    final repository = context.read<ClinicalRepository>();
    final encounter = await repository.startEncounter(
      patientId: widget.patient.id,
      clinicId: clinic.id,
      type: _type,
      chiefComplaint:
          _complaint.text.trim().isEmpty ? null : _complaint.text.trim(),
      providerName: session.signatureName,
    );

    if (mounted) Navigator.of(context).pop(encounter);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final m = context.metrics;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: m.spaceLg,
          right: m.spaceLg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + m.spaceLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Start visit', style: context.texts.titleMedium),
              Text(
                '${widget.patient.displayName} · '
                '${session.activeClinic?.name ?? 'No clinic'}',
                style: context.texts.bodySmall,
              ),
              SizedBox(height: m.spaceLg),
              ChoiceChipRow<EncounterType>(
                label: 'Visit type',
                values: EncounterType.values,
                labelOf: (t) => t.label,
                selected: _type,
                onSelected: (t) => setState(() => _type = t ?? _type),
              ),
              SizedBox(height: m.spaceLg),
              LabeledField(
                label: 'Presenting complaint',
                controller: _complaint,
                hint: "In the patient's own words",
                autofocus: true,
              ),
              SizedBox(height: m.spaceMd),
              Wrap(
                spacing: m.spaceSm,
                runSpacing: m.spaceSm,
                children: _commonComplaints.map((complaint) {
                  return ActionChip(
                    label: Text(complaint),
                    onPressed: () {
                      final current = _complaint.text.trim();
                      _complaint.text =
                          current.isEmpty ? complaint : '$current, $complaint';
                      _complaint.selection = TextSelection.collapsed(
                        offset: _complaint.text.length,
                      );
                    },
                  );
                }).toList(),
              ),
              SizedBox(height: m.spaceXl),
              FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start visit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
