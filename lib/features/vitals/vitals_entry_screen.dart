import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../clinical/news2.dart';
import '../../clinical/validators.dart';
import '../../clinical/vital_reference.dart';
import '../../core/session/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ids.dart';
import '../../data/models/patient.dart';
import '../../data/models/vitals_record.dart';
import '../../data/repositories/clinical_repository.dart';
import 'widgets/news2_preview.dart';
import 'widgets/pain_scale.dart';

/// Observation entry.
///
/// Field order follows the NEWS2 chart — respiration, saturation, oxygen,
/// blood pressure, pulse, consciousness, temperature — because that is the
/// order the observations are physically taken in, and matching it means the
/// user never has to hunt for the next box.
class VitalsEntryScreen extends StatefulWidget {
  const VitalsEntryScreen({
    super.key,
    required this.patientId,
    this.encounterId,
  });

  final String patientId;
  final String? encounterId;

  @override
  State<VitalsEntryScreen> createState() => _VitalsEntryScreenState();
}

class _VitalsEntryScreenState extends State<VitalsEntryScreen> {
  final TextEditingController _respiratoryRate = TextEditingController();
  final TextEditingController _spo2 = TextEditingController();
  final TextEditingController _oxygenFlow = TextEditingController();
  final TextEditingController _systolic = TextEditingController();
  final TextEditingController _diastolic = TextEditingController();
  final TextEditingController _heartRate = TextEditingController();
  final TextEditingController _temperature = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _height = TextEditingController();
  final TextEditingController _glucose = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  Consciousness _consciousness = Consciousness.alert;
  MeasurementPosition? _position = MeasurementPosition.sitting;
  TemperatureSite? _temperatureSite = TemperatureSite.oral;
  bool _onOxygen = false;
  int? _painScore;

  Patient? _patient;
  VitalsRecord? _previous;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _respiratoryRate,
      _spo2,
      _oxygenFlow,
      _systolic,
      _diastolic,
      _heartRate,
      _temperature,
      _weight,
      _height,
      _glucose,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repository = context.read<ClinicalRepository>();
    final patient = await repository.patients.byId(widget.patientId);
    final previous = await repository.vitals.latestForPatient(widget.patientId);
    if (!mounted) return;
    setState(() {
      _patient = patient;
      _previous = previous;
      _loading = false;
    });
  }

  /// Carries forward the values that genuinely do not change between visits.
  ///
  /// Height and weight only. Copying a previous blood pressure would put a
  /// number on the chart that nobody measured — the single most dangerous
  /// convenience an observation form can offer.
  void _copyStableValues() {
    final previous = _previous;
    if (previous == null) return;
    setState(() {
      if (previous.heightCm != null) {
        _height.text = Fmt.number(previous.heightCm);
      }
      if (previous.weightKg != null) {
        _weight.text = Fmt.number(previous.weightKg);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied height and weight. Measure the rest.'),
      ),
    );
  }

  int? _int(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  double? _double(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  News2Input get _news2Input => News2Input(
    respiratoryRate: _int(_respiratoryRate),
    spo2: _int(_spo2),
    onOxygen: _onOxygen,
    systolicBp: _int(_systolic),
    heartRate: _int(_heartRate),
    consciousness: _consciousness,
    temperatureC: _double(_temperature),
  );

  Future<void> _save() async {
    if (_busy) return;
    final patient = _patient;
    if (patient == null) return;

    final draft = VitalsRecord(
      id: newId(),
      patientId: patient.id,
      encounterId: widget.encounterId,
      recordedAt: DateTime.now(),
      position: _position,
      systolicBp: _int(_systolic),
      diastolicBp: _int(_diastolic),
      heartRate: _int(_heartRate),
      respiratoryRate: _int(_respiratoryRate),
      temperatureC: _double(_temperature),
      temperatureSite: _temperatureSite,
      spo2: _int(_spo2),
      onOxygen: _onOxygen,
      oxygenFlowLpm: _double(_oxygenFlow),
      consciousness: _consciousness,
      heightCm: _double(_height),
      weightKg: _double(_weight),
      painScore: _painScore,
      bloodGlucoseMmol: _double(_glucose),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      recordedBy: context.read<SessionController>().signatureName,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    if (draft.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one observation.')),
      );
      return;
    }

    setState(() => _busy = true);
    final repository = context.read<ClinicalRepository>();
    await repository.recordVitals(
      draft: draft,
      patientAgeYears: patient.age?.years,
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // The four observation groups, each its own builder.
  //
  // Extracted purely for depth: inline inside the two-column layout they
  // sat thirty columns deep, where every line wraps and the structure
  // stops being legible. They are ordered the way the observations are
  // physically taken, which is the order the NEWS2 chart uses.

  Widget _respiration() {
    final m = context.metrics;
    // Reference ranges are age-banded, so a paediatric helper
    // line depends on the loaded patient.
    final age = _patient?.age;
    return SectionCard(
      title: 'Respiration',
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: NumericField(
                  label: 'Resp rate',
                  controller: _respiratoryRate,
                  check: ClinicalValidators.respiratoryRate,
                  unit: '/min',
                  maxLength: 3,
                  helper:
                      'Normal ${VitalReference.respiratoryRate(age).display}',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(width: m.spaceMd),
              Expanded(
                child: NumericField(
                  label: 'SpO₂',
                  controller: _spo2,
                  check: ClinicalValidators.spo2,
                  unit: '%',
                  maxLength: 3,
                  helper: 'Normal ${VitalReference.spo2.display}',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          SizedBox(height: m.spaceMd),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _onOxygen,
            onChanged: (value) => setState(() => _onOxygen = value),
            title: const Text('On supplemental oxygen'),
            subtitle: const Text('Adds 2 to the NEWS2 score'),
          ),
          if (_onOxygen)
            NumericField(
              label: 'Oxygen flow',
              controller: _oxygenFlow,
              unit: 'L/min',
              allowDecimal: true,
              maxLength: 4,
            ),
        ],
      ),
    );
  }

  Widget _circulation() {
    final m = context.metrics;
    // Reference ranges are age-banded, so a paediatric helper
    // line depends on the loaded patient.
    final age = _patient?.age;
    return SectionCard(
      title: 'Circulation',
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: NumericField(
                  label: 'Systolic',
                  controller: _systolic,
                  check: ClinicalValidators.systolic,
                  unit: 'mmHg',
                  maxLength: 3,
                  helper: 'Normal ${VitalReference.systolic(age).display}',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(width: m.spaceMd),
              Expanded(
                child: NumericField(
                  label: 'Diastolic',
                  controller: _diastolic,
                  check: ClinicalValidators.diastolic,
                  unit: 'mmHg',
                  maxLength: 3,
                  helper: 'Normal ${VitalReference.diastolic(age).display}',
                ),
              ),
            ],
          ),
          SizedBox(height: m.spaceMd),
          NumericField(
            label: 'Pulse',
            controller: _heartRate,
            check: ClinicalValidators.heartRate,
            unit: 'bpm',
            maxLength: 3,
            helper: 'Normal ${VitalReference.heartRate(age).display}',
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: m.spaceLg),
          ChoiceChipRow<MeasurementPosition>(
            label: 'Position',
            values: MeasurementPosition.values,
            labelOf: (p) => p.label,
            selected: _position,
            onSelected: (p) => setState(() => _position = p),
          ),
        ],
      ),
    );
  }

  Widget _temperatureAndConsciousness() {
    final m = context.metrics;
    return SectionCard(
      title: 'Temperature & consciousness',
      child: Column(
        children: <Widget>[
          NumericField(
            label: 'Temperature',
            controller: _temperature,
            check: ClinicalValidators.temperatureC,
            unit: '°C',
            allowDecimal: true,
            maxLength: 5,
            helper: 'Normal ${VitalReference.temperature.display}',
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: m.spaceLg),
          ChoiceChipRow<TemperatureSite>(
            label: 'Site',
            values: TemperatureSite.values,
            labelOf: (s) => s.label,
            selected: _temperatureSite,
            onSelected: (s) => setState(() => _temperatureSite = s),
          ),
          SizedBox(height: m.spaceLg),
          ChoiceChipRow<Consciousness>(
            label: 'Consciousness (ACVPU)',
            values: Consciousness.values,
            labelOf: (c) => '${c.code} — ${c.label}',
            selected: _consciousness,
            onSelected: (c) =>
                setState(() => _consciousness = c ?? _consciousness),
          ),
        ],
      ),
    );
  }

  Widget _additional() {
    final m = context.metrics;
    return SectionCard(
      title: 'Additional',
      subtitle: 'Optional',
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: NumericField(
                  label: 'Weight',
                  controller: _weight,
                  check: ClinicalValidators.weightKg,
                  unit: 'kg',
                  allowDecimal: true,
                  maxLength: 5,
                ),
              ),
              SizedBox(width: m.spaceMd),
              Expanded(
                child: NumericField(
                  label: 'Height',
                  controller: _height,
                  check: ClinicalValidators.heightCm,
                  unit: 'cm',
                  allowDecimal: true,
                  maxLength: 5,
                ),
              ),
            ],
          ),
          SizedBox(height: m.spaceMd),
          NumericField(
            label: 'Blood glucose',
            controller: _glucose,
            check: ClinicalValidators.glucoseMmol,
            unit: 'mmol/L',
            allowDecimal: true,
            maxLength: 5,
          ),
          SizedBox(height: m.spaceLg),
          PainScale(
            value: _painScore,
            onChanged: (value) => setState(() => _painScore = value),
          ),
          SizedBox(height: m.spaceLg),
          LabeledField(
            label: 'Notes',
            controller: _notes,
            maxLines: 3,
            minLines: 2,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final patient = _patient;
    if (patient == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(),
        body: const Center(child: Text('Patient not found')),
      );
    }

    final m = context.metrics;
    final age = patient.age;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Record observations'),
        actions: <Widget>[
          if (_previous != null)
            TextButton(
              onPressed: _copyStableValues,
              child: const Text('Copy ht/wt'),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(m.spaceLg),
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Save observations'),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          PatientIdentityBar(patient: patient),
          Expanded(
            // Live score pinned above the scroll rather than scrolled with
            // it. In landscape with a keyboard up there is barely 300 logical
            // pixels of form visible, and a deteriorating patient's score
            // scrolling out of view is the one thing that must not happen
            // while the observations are still being typed.
            child: Column(
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    m.spaceLg,
                    m.spaceLg,
                    m.spaceLg,
                    0,
                  ),
                  child: ContentWidth.columns(
                    child: News2Preview(
                      input: _news2Input,
                      ageYears: age?.years,
                    ),
                  ),
                ),
                Expanded(
                  child: ContentWidth.columns(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(m.spaceLg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // Two columns on a wide screen. Respiration and
                          // circulation stay together on the left because that
                          // is the order the observations are physically taken
                          // in, which is the order the NEWS2 chart uses.
                          SplitColumns(
                            primaryFlex: 1,
                            secondaryFlex: 1,
                            primary: <Widget>[_respiration(), _circulation()],
                            secondary: <Widget>[
                              _temperatureAndConsciousness(),
                              _additional(),
                            ],
                          ),
                          SizedBox(height: m.space2xl),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
