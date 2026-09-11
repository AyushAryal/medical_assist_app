import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../clinical/patient_age.dart';
import '../../core/app_bootstrap.dart';
import '../../core/routing/app_router.dart';
import '../../core/session/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ids.dart';
import '../../data/models/allergy.dart';
import '../../data/models/patient.dart';
import '../../data/repositories/clinical_repository.dart';
import 'duplicate_warning_sheet.dart';

/// Registration and demographics editing.
///
/// Only four fields are required — given name, family name, sex and either a
/// date of birth or an age. Everything else can be filled in later. A long
/// mandatory form at the front desk is how patients end up registered as
/// "Unknown Unknown" with the real details never captured at all.
class PatientFormScreen extends StatefulWidget {
  const PatientFormScreen({super.key, this.patientId});

  final String? patientId;

  bool get isEditing => patientId != null;

  @override
  State<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends State<PatientFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _given = TextEditingController();
  final TextEditingController _family = TextEditingController();
  final TextEditingController _preferred = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _nationalId = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _kinName = TextEditingController();
  final TextEditingController _kinPhone = TextEditingController();
  final TextEditingController _ageEntry = TextEditingController();

  SexAtBirth _sex = SexAtBirth.unknown;
  AllergyStatus _allergyStatus = AllergyStatus.unknown;

  /// Allergies captured during registration, written right after the patient
  /// record is created. Registration is when the question is actually asked —
  /// sending the clerk into the chart afterwards is how the answer gets lost.
  final List<Allergy> _newAllergies = <Allergy>[];
  DateTime? _dateOfBirth;
  bool _dobIsEstimated = false;
  Patient? _existing;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _given, _family, _preferred, _phone, _nationalId,
      _city, _address, _kinName, _kinPhone, _ageEntry,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (!widget.isEditing) {
      setState(() => _loading = false);
      return;
    }
    final repository = context.read<ClinicalRepository>();
    final patient = await repository.patients.byId(widget.patientId!);
    if (!mounted || patient == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _existing = patient;
      _given.text = patient.givenName;
      _family.text = patient.familyName;
      _preferred.text = patient.preferredName ?? '';
      _phone.text = patient.phone ?? '';
      _nationalId.text = patient.nationalId ?? '';
      _city.text = patient.city ?? '';
      _address.text = patient.addressLine ?? '';
      _kinName.text = patient.nextOfKinName ?? '';
      _kinPhone.text = patient.nextOfKinPhone ?? '';
      _sex = patient.sexAtBirth;
      _allergyStatus = patient.allergyStatus;
      _dateOfBirth = patient.dateOfBirth;
      _dobIsEstimated = patient.dobIsEstimated;
      _loading = false;
    });
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(now.year - 130),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked == null) return;
    setState(() {
      _dateOfBirth = picked;
      _dobIsEstimated = false;
      _ageEntry.clear();
    });
  }

  /// Age-to-DOB entry. Many patients — especially older ones and those without
  /// birth registration — know their age but not their date of birth. Deriving
  /// a 1 January date and flagging it as estimated keeps age arithmetic working
  /// without inventing a precise birthday that the record would then assert.
  void _applyEstimatedAge(String value) {
    final years = int.tryParse(value);
    if (years == null || years < 0 || years > 130) return;
    setState(() {
      _dateOfBirth = DateTime(DateTime.now().year - years, 1, 1);
      _dobIsEstimated = true;
    });
  }

  /// Offers any existing records that look like the same person.
  ///
  /// Returns true to go ahead with registration. It **never** blocks: the
  /// patient is standing at the desk, and a check that can refuse to create a
  /// record gets worked around within a week — usually by misspelling the name
  /// on purpose, which produces the exact duplicate it was meant to prevent.
  /// Everything here is advisory, and continuing is always one tap.
  Future<bool> _confirmNotDuplicate(Patient draft) async {
    final repository = context.read<ClinicalRepository>();
    final assist = context.read<AppBootstrap>().assist;

    // Search the register by the draft's own name parts rather than scanning
    // every record: the similarity comparison is cheap, but loading a whole
    // clinic's register into memory to run it is not.
    final byName = <Patient>[
      ...await repository.patients.search(draft.familyName),
      ...await repository.patients.search(draft.givenName),
      if (draft.phone?.isNotEmpty ?? false)
        ...await repository.patients.search(draft.phone!),
    ];
    final unique = <String, Patient>{
      for (final patient in byName) patient.id: patient,
    };

    final candidates = assist.possibleDuplicates(
      candidate: draft,
      register: unique.values,
    );
    if (candidates.isEmpty || !mounted) return true;

    final choice = await DuplicateWarningSheet.show(
      context,
      draft: draft,
      candidates: candidates,
    );
    if (choice == null || !mounted) return false;

    if (choice.openExistingId case final existingId?) {
      Navigator.of(context).pop();
      await context.push(Routes.chartFor(existingId));
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    if (_dateOfBirth == null) {
      _showMessage('Enter a date of birth or an approximate age.');
      return;
    }

    setState(() => _busy = true);
    final repository = context.read<ClinicalRepository>();
    final session = context.read<SessionController>();
    final now = DateTime.now();

    final draft = Patient(
      id: _existing?.id ?? newId(),
      mrn: _existing?.mrn ?? '',
      familyName: _family.text.trim(),
      givenName: _given.text.trim(),
      preferredName: _nullIfBlank(_preferred.text),
      sexAtBirth: _sex,
      dateOfBirth: _dateOfBirth,
      dobIsEstimated: _dobIsEstimated,
      phone: _nullIfBlank(_phone.text),
      nationalId: _nullIfBlank(_nationalId.text),
      addressLine: _nullIfBlank(_address.text),
      city: _nullIfBlank(_city.text),
      nextOfKinName: _nullIfBlank(_kinName.text),
      nextOfKinPhone: _nullIfBlank(_kinPhone.text),
      primaryClinicId: _existing?.primaryClinicId ?? session.activeClinic?.id,
      allergyStatus: _allergyStatus,
      lastSeenAt: _existing?.lastSeenAt,
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
      revision: _existing?.revision ?? 1,
    );

    // Captured before the pop: after this route is gone its own context can no
    // longer resolve a ScaffoldMessenger, and the confirmation would be
    // silently dropped.
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (_existing == null) {
        // Duplicate check happens here, between building the record and
        // writing it — late enough to compare the finished details, early
        // enough that nothing has been created yet.
        if (!await _confirmNotDuplicate(draft)) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        if (!mounted) return;

        final created = await repository.createPatient(draft);
        for (final allergy in _newAllergies) {
          await repository.patients.addAllergy(
            Allergy(
              id: allergy.id,
              patientId: created.id,
              substance: allergy.substance,
              category: allergy.category,
              reaction: allergy.reaction,
              severity: allergy.severity,
              createdAt: allergy.createdAt,
              updatedAt: allergy.updatedAt,
            ),
          );
        }
        if (!mounted) return;
        Navigator.of(context).pop(created.id);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Registered ${created.displayName} — MRN ${created.mrn}',
            ),
          ),
        );
      } else {
        await repository.updatePatient(
          draft,
          changedFields: 'demographics',
        );
        if (!mounted) return;
        Navigator.of(context).pop(draft.id);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage('Could not save: $error');
    }
  }

  Future<void> _addAllergy() async {
    final allergy = await _RegistrationAllergySheet.show(context);
    if (allergy == null) return;
    setState(() {
      _newAllergies.add(allergy);
      // An entered allergy answers the status question by itself.
      _allergyStatus = AllergyStatus.hasAllergies;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static String? _nullIfBlank(String value) =>
      value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final age = PatientAge.fromDateOfBirth(_dateOfBirth);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit patient' : 'New patient'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(widget.isEditing ? 'Save' : 'Register'),
          ),
        ],
      ),
      body: ContentWidth(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(m.spaceLg),
            children: <Widget>[
              SectionCard(
                title: 'Identity',
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: LabeledField(
                            label: 'Given name',
                            controller: _given,
                            autofocus: !widget.isEditing,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? 'Required'
                                : null,
                          ),
                        ),
                        SizedBox(width: m.spaceMd),
                        Expanded(
                          child: LabeledField(
                            label: 'Family name',
                            controller: _family,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? 'Required'
                                : null,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: m.spaceMd),
                    LabeledField(
                      label: 'Preferred name (optional)',
                      controller: _preferred,
                      textCapitalization: TextCapitalization.words,
                    ),
                    SizedBox(height: m.spaceLg),
                    ChoiceChipRow<SexAtBirth>(
                      label: 'Sex at birth',
                      values: SexAtBirth.values,
                      labelOf: (s) => s.label,
                      selected: _sex,
                      onSelected: (s) => setState(() => _sex = s ?? _sex),
                    ),
                    SizedBox(height: m.spaceXs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Used for reference ranges and dosing, not for how the '
                        'patient is addressed.',
                        style: context.texts.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: m.spaceMd),

              SectionCard(
                title: 'Age',
                subtitle: 'Exact date if known, otherwise an approximate age',
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          flex: 3,
                          child: OutlinedButton.icon(
                            onPressed: _pickDateOfBirth,
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(
                              _dateOfBirth == null
                                  ? 'Date of birth'
                                  : Fmt.date(_dateOfBirth),
                            ),
                          ),
                        ),
                        SizedBox(width: m.spaceMd),
                        Expanded(
                          flex: 2,
                          child: NumericField(
                            label: 'or age',
                            controller: _ageEntry,
                            unit: 'yr',
                            maxLength: 3,
                            onChanged: _applyEstimatedAge,
                          ),
                        ),
                      ],
                    ),
                    if (age != null) ...<Widget>[
                      SizedBox(height: m.spaceMd),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _dobIsEstimated
                              ? 'Approximately ${age.label} — recorded as an '
                                  'estimate'
                              : '${age.label} old',
                          style: context.texts.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: m.spaceMd),

              SectionCard(
                title: 'Allergies',
                subtitle: 'Ask at registration — it cannot be assumed later',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ChoiceChipRow<AllergyStatus>(
                      values: AllergyStatus.values,
                      labelOf: (s) => s.label,
                      selected: _allergyStatus,
                      onSelected: (s) =>
                          setState(() => _allergyStatus = s ?? _allergyStatus),
                    ),
                    if (!widget.isEditing) ...<Widget>[
                      for (final allergy in _newAllergies)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            Icons.warning_amber_outlined,
                            size: 18,
                            color: context.palette.caution,
                          ),
                          title: Text(allergy.substance),
                          subtitle: allergy.reaction == null
                              ? Text(allergy.severity.label)
                              : Text(
                                  '${allergy.reaction} · '
                                  '${allergy.severity.label}',
                                ),
                          trailing: IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setState(() => _newAllergies.remove(allergy)),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addAllergy,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add allergy'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: m.spaceMd),

              SectionCard(
                title: 'Contact',
                child: Column(
                  children: <Widget>[
                    LabeledField(
                      label: 'Phone',
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
                      ],
                    ),
                    SizedBox(height: m.spaceMd),
                    LabeledField(label: 'Address', controller: _address),
                    SizedBox(height: m.spaceMd),
                    LabeledField(label: 'City / town', controller: _city),
                    SizedBox(height: m.spaceMd),
                    LabeledField(
                      label: 'National ID (optional)',
                      controller: _nationalId,
                    ),
                  ],
                ),
              ),
              SizedBox(height: m.spaceMd),

              SectionCard(
                title: 'Next of kin',
                subtitle: 'Who to contact if the patient cannot consent',
                child: Column(
                  children: <Widget>[
                    LabeledField(
                      label: 'Name',
                      controller: _kinName,
                      textCapitalization: TextCapitalization.words,
                    ),
                    SizedBox(height: m.spaceMd),
                    LabeledField(
                      label: 'Phone',
                      controller: _kinPhone,
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                ),
              ),
              SizedBox(height: m.spaceXl),

              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(
                  widget.isEditing ? 'Save changes' : 'Register patient',
                ),
              ),
              SizedBox(height: m.space2xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Allergy entry at registration — same fields as the chart's sheet, but it
/// returns the draft instead of writing it: the patient does not exist yet.
class _RegistrationAllergySheet extends StatefulWidget {
  const _RegistrationAllergySheet();

  static Future<Allergy?> show(BuildContext context) {
    return showModalBottomSheet<Allergy>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _RegistrationAllergySheet(),
    );
  }

  @override
  State<_RegistrationAllergySheet> createState() =>
      _RegistrationAllergySheetState();
}

class _RegistrationAllergySheetState extends State<_RegistrationAllergySheet> {
  final TextEditingController _substance = TextEditingController();
  final TextEditingController _reaction = TextEditingController();
  AllergyCategory _category = AllergyCategory.drug;
  AllergySeverity _severity = AllergySeverity.unknown;

  @override
  void dispose() {
    _substance.dispose();
    _reaction.dispose();
    super.dispose();
  }

  void _save() {
    if (_substance.text.trim().isEmpty) return;
    final now = DateTime.now();
    Navigator.of(context).pop(
      Allergy(
        id: newId(),
        // Replaced with the real id once the patient record exists.
        patientId: '',
        substance: _substance.text.trim(),
        category: _category,
        reaction:
            _reaction.text.trim().isEmpty ? null : _reaction.text.trim(),
        severity: _severity,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SheetScaffold(
      title: 'Add allergy',
      onSave: _save,
      saveLabel: 'Add',
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
      ],
    );
  }
}
