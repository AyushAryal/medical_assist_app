import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/routing/app_router.dart';
import '../../core/session/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/allergy.dart';
import '../../data/models/clinical_note.dart';
import '../../data/models/encounter.dart';
import '../../data/models/patient.dart';
import '../../data/models/vitals_record.dart';
import '../../data/repositories/clinical_repository.dart';
import '../vitals/vitals_summary_card.dart';

/// The encounter workspace: observations, note and disposition for one visit,
/// ending in a signature.
class EncounterScreen extends StatefulWidget {
  const EncounterScreen({super.key, required this.encounterId});

  final String encounterId;

  @override
  State<EncounterScreen> createState() => _EncounterScreenState();
}

class _EncounterScreenState extends State<EncounterScreen> {
  Encounter? _encounter;
  Patient? _patient;
  ClinicalNote? _note;
  List<VitalsRecord> _vitals = const <VitalsRecord>[];
  List<Allergy> _allergies = const <Allergy>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repository = context.read<ClinicalRepository>();
    final encounter = await repository.encounters.byId(widget.encounterId);
    if (encounter == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final patient = await repository.patients.byId(encounter.patientId);
    final note = await repository.notes.forEncounter(encounter.id);
    final vitals = await repository.vitals.forEncounter(encounter.id);
    final allergies = await repository.patients.allergies(encounter.patientId);

    if (!mounted) return;
    setState(() {
      _encounter = encounter;
      _patient = patient;
      _note = note;
      _vitals = vitals;
      _allergies = allergies;
      _loading = false;
    });
  }

  Future<void> _sign() async {
    final encounter = _encounter;
    final note = _note;
    if (encounter == null) return;

    if (note == null || note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Write the clinical note before signing.'),
        ),
      );
      return;
    }

    final session = context.read<SessionController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign this encounter?'),
        content: Text(
          'Signing locks the note as the final record of this visit. '
          'It cannot be edited afterwards — corrections are added as '
          'amendments, which remain visible in the record.\n\n'
          'Signing as ${session.signatureName}.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final repository = context.read<ClinicalRepository>();
    await repository.signEncounter(
      encounter: encounter,
      signedBy: session.signatureName,
    );
    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Encounter signed.')));
  }

  Future<void> _setDisposition(Disposition disposition) async {
    final encounter = _encounter;
    if (encounter == null || encounter.isLocked) return;
    final repository = context.read<ClinicalRepository>();
    await repository.updateEncounter(
      encounter.copyWith(disposition: disposition),
    );
    await _load();
  }

  Future<void> _setFollowUp() async {
    final encounter = _encounter;
    if (encounter == null || encounter.isLocked) return;

    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'Follow-up date',
    );
    if (picked == null || !mounted) return;

    final repository = context.read<ClinicalRepository>();
    await repository.updateEncounter(encounter.copyWith(followUpDate: picked));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final encounter = _encounter;
    final patient = _patient;
    if (encounter == null || patient == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'Encounter not found',
        ),
      );
    }

    final m = context.metrics;
    final isLocked = encounter.isLocked;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(encounter.type.label),
        actions: <Widget>[
          Padding(
            padding: EdgeInsets.only(right: m.spaceMd),
            child: Center(
              child: StatusPill(
                label: encounter.status.label,
                tone: isLocked ? PillTone.normal : PillTone.caution,
                icon: isLocked ? Icons.lock_outline : Icons.edit_outlined,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isLocked
          ? null
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.all(m.spaceLg),
                child: FilledButton.icon(
                  onPressed: _sign,
                  icon: const Icon(Icons.draw_outlined),
                  label: const Text('Sign & close encounter'),
                ),
              ),
            ),
      body: Column(
        children: <Widget>[
          PatientIdentityBar(
            patient: patient,
            onTap: () => context.push(Routes.chartFor(patient.id)),
            trailing: const Icon(Icons.chevron_right),
          ),
          AllergyBanner(status: patient.allergyStatus, allergies: _allergies),
          Expanded(
            // The note is what the visit is *for*, so it leads the primary
            // column; the surrounding facts sit beside it on a wide screen
            // instead of pushing it below the fold.
            child: ContentWidth.columns(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  m.spaceLg,
                  m.spaceLg,
                  m.spaceLg,
                  m.space2xl,
                ),
                child: SplitColumns(
                  primary: <Widget>[
                    _NoteCard(
                      note: _note,
                      isLocked: isLocked,
                      onOpen: () async {
                        await context.push(Routes.noteFor(encounter.id));
                        await _load();
                      },
                    ),
                    if (_vitals.isEmpty)
                      SectionCard(
                        title: 'Observations',
                        leading: const Icon(
                          Icons.monitor_heart_outlined,
                          size: 20,
                        ),
                        child: EmptyState(
                          icon: Icons.monitor_heart_outlined,
                          title: 'No observations for this visit',
                          actionLabel: isLocked ? null : 'Record observations',
                          onAction: isLocked
                              ? null
                              : () async {
                                  await context.push(
                                    '${Routes.vitalsFor(patient.id)}'
                                    '?encounterId=${encounter.id}',
                                  );
                                  await _load();
                                },
                          compact: true,
                        ),
                      )
                    else
                      VitalsSummaryCard(
                        vitals: _vitals.first,
                        previous: _vitals.length > 1 ? _vitals[1] : null,
                        age: patient.age,
                        onRecord: isLocked
                            ? null
                            : () async {
                                await context.push(
                                  '${Routes.vitalsFor(patient.id)}'
                                  '?encounterId=${encounter.id}',
                                );
                                await _load();
                              },
                      ),
                  ],
                  secondary: <Widget>[
                    SectionCard(
                      title: 'Visit',
                      leading: const Icon(Icons.event_note_outlined, size: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _DetailRow(
                            label: 'Started',
                            value: Fmt.dateTime(encounter.startedAt),
                          ),
                          if (encounter.chiefComplaint != null)
                            _DetailRow(
                              label: 'Complaint',
                              value: encounter.chiefComplaint!,
                            ),
                          if (encounter.providerName != null)
                            _DetailRow(
                              label: 'Clinician',
                              value: encounter.providerName!,
                            ),
                          if (encounter.followUpDate != null)
                            _DetailRow(
                              label: 'Follow-up',
                              value: Fmt.date(encounter.followUpDate),
                            ),
                        ],
                      ),
                    ),
                    SectionCard(
                      title: 'Disposition',
                      subtitle: 'Where the patient goes next',
                      leading: const Icon(Icons.logout_outlined, size: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          ChoiceChipRow<Disposition>(
                            values: Disposition.values,
                            labelOf: (d) => d.label,
                            selected: encounter.disposition,
                            onSelected: (d) {
                              if (d != null) _setDisposition(d);
                            },
                          ),
                          SizedBox(height: m.spaceLg),
                          OutlinedButton.icon(
                            onPressed: isLocked ? null : _setFollowUp,
                            icon: const Icon(Icons.event_repeat_outlined),
                            label: Text(
                              encounter.followUpDate == null
                                  ? 'Set follow-up date'
                                  : 'Follow-up '
                                        '${Fmt.date(encounter.followUpDate)}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.isLocked,
    required this.onOpen,
  });

  final ClinicalNote? note;
  final bool isLocked;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final sections = note?.filledSectionCount ?? 0;

    return SectionCard(
      title: 'Clinical note',
      subtitle: note == null
          ? 'Not started'
          : '${note!.noteType.label} · $sections of 4 sections',
      leading: const Icon(Icons.description_outlined, size: 20),
      trailing: Icon(isLocked ? Icons.lock_outline : Icons.chevron_right),
      onTap: onOpen,
      child: note == null || note!.isEmpty
          ? EmptyState(
              icon: Icons.edit_note,
              title: isLocked ? 'No note was recorded' : 'Write the note',
              message: isLocked
                  ? null
                  : 'Subjective, objective, assessment and plan.',
              compact: true,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (note!.assessment?.isNotEmpty == true)
                  _NotePreview(label: 'A', body: note!.assessment!),
                if (note!.plan?.isNotEmpty == true)
                  _NotePreview(label: 'P', body: note!.plan!),
              ],
            ),
    );
  }
}

class _NotePreview extends StatelessWidget {
  const _NotePreview({required this.label, required this.body});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 20,
            child: Text(label, style: context.texts.labelLarge),
          ),
          Expanded(
            child: Text(
              body,
              style: context.texts.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(label, style: context.texts.labelMedium),
          ),
          Expanded(child: Text(value, style: context.texts.bodyMedium)),
        ],
      ),
    );
  }
}
