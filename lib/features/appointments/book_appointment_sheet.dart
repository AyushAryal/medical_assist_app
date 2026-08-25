import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/session/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/appointment.dart';
import '../../data/models/encounter.dart';
import '../../data/models/patient.dart';
import '../../data/repositories/clinical_repository.dart';

/// Books or reschedules a slot.
///
/// Deliberately short: date, time, length, reason. Anything longer and the
/// front desk books on paper instead. Conflicts are surfaced as a warning
/// rather than a block — double-booking is sometimes the right call, and the
/// software should not pretend to know better than the person at the desk.
class BookAppointmentSheet extends StatefulWidget {
  const BookAppointmentSheet({
    super.key,
    required this.patient,
    this.existing,
  });

  final Patient patient;
  final Appointment? existing;

  static Future<Appointment?> show(
    BuildContext context, {
    required Patient patient,
    Appointment? existing,
  }) {
    return showModalBottomSheet<Appointment>(
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
        child: BookAppointmentSheet(patient: patient, existing: existing),
      ),
    );
  }

  @override
  State<BookAppointmentSheet> createState() => _BookAppointmentSheetState();
}

class _BookAppointmentSheetState extends State<BookAppointmentSheet> {
  final TextEditingController _reason = TextEditingController();

  late DateTime _date;
  late TimeOfDay _time;
  late int _duration;
  late EncounterType _type;
  List<Appointment> _conflicts = const <Appointment>[];
  bool _busy = false;

  static const List<int> _durations = <int>[10, 15, 20, 30, 45, 60];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final seed = existing?.scheduledAt ?? _nextRoundedSlot();
    _date = DateTime(seed.year, seed.month, seed.day);
    _time = TimeOfDay(hour: seed.hour, minute: seed.minute);
    _duration = existing?.durationMinutes ?? 15;
    _type = existing?.type ?? EncounterType.followUp;
    _reason.text = existing?.reason ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkConflicts());
  }

  /// Defaults to the next quarter-hour, which is what someone booking "now"
  /// almost always wants.
  static DateTime _nextRoundedSlot() {
    final now = DateTime.now().add(const Duration(minutes: 15));
    final minute = (now.minute / 15).ceil() * 15;
    return DateTime(now.year, now.month, now.day, now.hour)
        .add(Duration(minutes: minute));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  DateTime get _scheduledAt => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      );

  Future<void> _checkConflicts() async {
    final session = context.read<SessionController>();
    final clinic = session.activeClinic;
    if (clinic == null) return;

    final conflicts = await context.read<ClinicalRepository>().appointments.conflicts(
          clinicId: clinic.id,
          start: _scheduledAt,
          durationMinutes: _duration,
          excludingId: widget.existing?.id,
        );
    if (!mounted) return;
    setState(() => _conflicts = conflicts);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Appointment date',
    );
    if (picked == null) return;
    setState(() => _date = picked);
    await _checkConflicts();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Appointment time',
    );
    if (picked == null) return;
    setState(() => _time = picked);
    await _checkConflicts();
  }

  Future<void> _save() async {
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
    final reason = _reason.text.trim().isEmpty ? null : _reason.text.trim();

    final Appointment result;
    if (widget.existing != null) {
      result = await repository.rescheduleAppointment(
        widget.existing!.copyWith(reason: reason, type: _type),
        _scheduledAt,
        durationMinutes: _duration,
      );
    } else {
      result = await repository.bookAppointment(
        patientId: widget.patient.id,
        clinicId: clinic.id,
        scheduledAt: _scheduledAt,
        durationMinutes: _duration,
        type: _type,
        reason: reason,
        providerName: session.signatureName,
      );
    }

    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

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
              Text(
                widget.existing == null ? 'Book appointment' : 'Reschedule',
                style: context.texts.titleMedium,
              ),
              Text(
                '${widget.patient.displayName} · ${widget.patient.identityLine}',
                style: context.texts.bodySmall,
              ),
              SizedBox(height: m.spaceLg),

              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        Fmt.dateShort(_date),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SizedBox(width: m.spaceSm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule, size: 16),
                      label: Text(
                        _time.format(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: m.spaceLg),

              ChoiceChipRow<int>(
                label: 'Length',
                values: _durations,
                labelOf: (d) => '$d min',
                selected: _duration,
                onSelected: (d) async {
                  setState(() => _duration = d ?? _duration);
                  await _checkConflicts();
                },
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
                label: 'Reason for visit',
                controller: _reason,
                hint: 'e.g. Diabetes review',
              ),

              if (_conflicts.isNotEmpty) ...<Widget>[
                SizedBox(height: m.spaceLg),
                Container(
                  padding: EdgeInsets.all(m.spaceMd),
                  decoration: BoxDecoration(
                    color: palette.cautionSubtle,
                    borderRadius: BorderRadius.circular(m.radiusSm),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.info_outline, size: 16, color: palette.caution),
                      SizedBox(width: m.spaceSm),
                      Expanded(
                        child: Text(
                          'Overlaps ${_conflicts.length} existing '
                          'appointment${_conflicts.length == 1 ? '' : 's'} at '
                          'this clinic. You can still book if that is intended.',
                          style: context.texts.bodySmall
                              ?.copyWith(color: palette.caution),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: m.spaceXl),
              Row(
                children: <Widget>[
                  StatusPill(
                    label: Fmt.dateTime(_scheduledAt),
                    tone: PillTone.info,
                    icon: Icons.event,
                    dense: true,
                  ),
                ],
              ),
              SizedBox(height: m.spaceMd),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(
                  widget.existing == null ? 'Book appointment' : 'Reschedule',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
