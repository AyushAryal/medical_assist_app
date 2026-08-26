import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/session/session_controller.dart';
import '../../data/models/clinic.dart';
import '../../data/repositories/clinical_repository.dart';

class ClinicListScreen extends StatelessWidget {
  const ClinicListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final m = context.metrics;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Clinics')),
      floatingActionButton: FloatingActionButton.extended(
        // Distinct tag: default FAB tags collide across the IndexedStack
        // shell tabs, which are all mounted at once.
        heroTag: 'clinicListFab',
        onPressed: () => _ClinicEditorSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Add clinic'),
      ),
      body: ContentWidth(
        child: session.clinics.isEmpty
            ? const EmptyState(
                icon: Icons.local_hospital_outlined,
                title: 'No clinics yet',
                message: 'Add the sites where you see patients.',
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  m.spaceLg,
                  m.spaceLg,
                  m.spaceLg,
                  m.space2xl * 2,
                ),
                itemCount: session.clinics.length,
                separatorBuilder: (_, _) => SizedBox(height: m.spaceSm),
                itemBuilder: (context, index) {
                  final clinic = session.clinics[index];
                  final isActive = clinic.id == session.activeClinic?.id;
                  return GlassPanel(
                    padding: EdgeInsets.symmetric(horizontal: m.spaceMd),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(clinic.name),
                      subtitle: Text(
                        <String>[
                          clinic.type.label,
                          if (clinic.locationLabel.isNotEmpty)
                            clinic.locationLabel,
                          if (clinic.phone?.isNotEmpty == true) clinic.phone!,
                        ].join(' · '),
                      ),
                      trailing: isActive
                          ? const StatusPill(
                              label: 'Active',
                              tone: PillTone.info,
                              dense: true,
                            )
                          : TextButton(
                              onPressed: () => session.setActiveClinic(clinic),
                              child: const Text('Use'),
                            ),
                      onTap: () =>
                          _ClinicEditorSheet.show(context, clinic: clinic),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _ClinicEditorSheet extends StatefulWidget {
  const _ClinicEditorSheet({this.clinic});

  final Clinic? clinic;

  static Future<void> show(BuildContext context, {Clinic? clinic}) {
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
        child: _ClinicEditorSheet(clinic: clinic),
      ),
    );
  }

  @override
  State<_ClinicEditorSheet> createState() => _ClinicEditorSheetState();
}

class _ClinicEditorSheetState extends State<_ClinicEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.clinic?.name ?? '');
  late final TextEditingController _city =
      TextEditingController(text: widget.clinic?.city ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.clinic?.phone ?? '');
  late ClinicType _type = widget.clinic?.type ?? ClinicType.clinic;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() => _busy = true);

    final repository = context.read<ClinicalRepository>();
    final session = context.read<SessionController>();
    final existing = widget.clinic;

    if (existing == null) {
      await repository.clinics.create(
        name: _name.text.trim(),
        type: _type,
        city: _city.text.trim(),
        phone: _phone.text.trim(),
      );
    } else {
      await repository.clinics.update(
        existing.copyWith(
          name: _name.text.trim(),
          type: _type,
          city: _city.text.trim(),
          phone: _phone.text.trim(),
        ),
      );
    }

    await session.refreshClinics();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Padding(
      padding: EdgeInsets.only(
        left: m.spaceLg,
        right: m.spaceLg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + m.spaceLg,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.clinic == null ? 'Add clinic' : 'Edit clinic',
              style: context.texts.titleMedium,
            ),
            SizedBox(height: m.spaceLg),
            LabeledField(
              label: 'Name',
              controller: _name,
              autofocus: true,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'A clinic needs a name'
                  : null,
            ),
            SizedBox(height: m.spaceMd),
            ChoiceChipRow<ClinicType>(
              label: 'Type',
              values: ClinicType.values,
              labelOf: (t) => t.label,
              selected: _type,
              onSelected: (t) => setState(() => _type = t ?? _type),
            ),
            SizedBox(height: m.spaceMd),
            LabeledField(label: 'City / town', controller: _city),
            SizedBox(height: m.spaceMd),
            LabeledField(
              label: 'Phone',
              controller: _phone,
              keyboardType: TextInputType.phone,
            ),
            SizedBox(height: m.spaceLg),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(widget.clinic == null ? 'Add clinic' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
