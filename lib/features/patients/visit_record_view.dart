import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/design.dart';
import '../../core/routing/app_router.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/clinical_note.dart';
import '../../data/models/encounter.dart';
import '../../data/models/patient.dart';
import '../vitals/vitals_summary_card.dart';
import 'patient_chart_controller.dart';

/// One past visit, laid out to be *read*.
///
/// The distinction this draws is between an editor and a record. The note
/// editor is four labelled text fields with a microphone and an attach bar on
/// each — correct for writing, and hostile for reading, because the chrome
/// outweighs the content and empty sections take up as much room as full ones.
///
/// What a clinician does with last month's visit is skim it in about fifteen
/// seconds looking for what was found and what was done. So here: empty
/// sections vanish, the observations taken during the visit sit inline rather
/// than a screen away, the section letters carry the structure without a border
/// each, and the signature is stated once at the bottom where a signature
/// belongs. Nothing is editable, which is why nothing needs to look editable.
class VisitRecordView extends StatelessWidget {
  const VisitRecordView({
    super.key,
    required this.visit,
    required this.patient,
    required this.age,
    this.dense = false,
  });

  final VisitRecord visit;
  final Patient patient;
  final dynamic age;

  /// Trims the vertical rhythm for use inside a history list rather than as a
  /// screen of its own.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final note = visit.note;
    final encounter = visit.encounter;

    final sections = <({String letter, String label, String? body})>[
      (letter: 'S', label: 'Subjective', body: note?.subjective),
      (letter: 'O', label: 'Objective', body: note?.objective),
      (letter: 'A', label: 'Assessment', body: note?.assessment),
      (letter: 'P', label: 'Plan', body: note?.plan),
    ].where((s) => (s.body?.trim().isNotEmpty ?? false)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _VisitHeader(encounter: encounter, note: note),
        SizedBox(height: dense ? m.spaceMd : m.spaceLg),

        if (encounter.chiefComplaint?.trim().isNotEmpty ?? false) ...<Widget>[
          _Quoted(text: encounter.chiefComplaint!),
          SizedBox(height: m.spaceMd),
        ],

        // Observations taken during this visit, in the same card the chart
        // uses. A number recorded at the visit belongs beside the note about
        // the visit, not on a separate screen reached by remembering to look.
        for (final vitals in visit.vitals) ...<Widget>[
          VitalsSummaryCard(vitals: vitals, age: age),
          SizedBox(height: m.spaceMd),
        ],

        if (sections.isEmpty && note != null)
          Padding(
            padding: EdgeInsets.only(bottom: m.spaceMd),
            child: Text(
              note.isEmpty
                  ? 'No note was written for this visit.'
                  : 'The note for this visit is empty.',
              style: context.texts.bodySmall,
            ),
          ),

        for (final section in sections) ...<Widget>[
          _NoteSection(
            letter: section.letter,
            label: section.label,
            body: section.body!,
          ),
          SizedBox(height: dense ? m.spaceSm : m.spaceMd),
        ],

        if (visit.attachments.isNotEmpty) ...<Widget>[
          SizedBox(height: m.spaceXs),
          _AttachmentSummary(count: visit.attachments.length),
          SizedBox(height: m.spaceMd),
        ],

        _Disposition(encounter: encounter),

        if (note != null && note.isLocked) ...<Widget>[
          SizedBox(height: m.spaceMd),
          _Signature(note: note),
        ],

        if (!dense) ...<Widget>[
          SizedBox(height: m.spaceLg),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.encounterFor(encounter.id)),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open the full visit record'),
          ),
        ],
      ],
    );
  }
}

class _VisitHeader extends StatelessWidget {
  const _VisitHeader({required this.encounter, required this.note});

  final Encounter encounter;
  final ClinicalNote? note;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                Fmt.dateTime(encounter.startedAt),
                style: context.texts.titleMedium,
              ),
              SizedBox(height: m.spaceXs / 2),
              Text(
                <String>[
                  encounter.type.label,
                  if (encounter.providerName?.isNotEmpty ?? false)
                    encounter.providerName!,
                ].join(' · '),
                style: context.texts.bodySmall,
              ),
            ],
          ),
        ),
        StatusPill(
          label: encounter.status.label,
          tone: switch (encounter.status) {
            EncounterStatus.signed || EncounterStatus.amended =>
              PillTone.normal,
            EncounterStatus.cancelled => PillTone.neutral,
            _ => PillTone.caution,
          },
          icon: note?.isLocked ?? false ? Icons.lock_outline : null,
          dense: true,
        ),
        if (!(note?.isLocked ?? true)) ...<Widget>[
          SizedBox(width: m.spaceXs),
          Icon(Icons.edit_note, size: 16, color: palette.caution),
        ],
      ],
    );
  }
}

/// The presenting complaint, in the patient's own words.
class _Quoted extends StatelessWidget {
  const _Quoted({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.only(left: m.spaceMd),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: palette.accent, width: 2.5),
        ),
      ),
      child: Text(
        text.trim(),
        style: context.texts.bodyLarge?.copyWith(
          fontStyle: FontStyle.italic,
          height: 1.35,
        ),
      ),
    );
  }
}

/// One SOAP section as prose: a letter, a label, and the text.
///
/// No card and no border. Four bordered panels for four paragraphs turns a
/// note into a form, and the reader spends attention on the boxes rather than
/// on what was written in them.
class _NoteSection extends StatelessWidget {
  const _NoteSection({
    required this.letter,
    required this.label,
    required this.body,
  });

  final String letter;
  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 26,
          child: Text(
            letter,
            style: context.texts.titleMedium?.copyWith(
              color: palette.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label.toUpperCase(),
                style: context.texts.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  color: palette.onSurfaceMuted,
                ),
              ),
              SizedBox(height: m.spaceXs / 2),
              Text(
                body.trim(),
                style: context.texts.bodyMedium?.copyWith(height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AttachmentSummary extends StatelessWidget {
  const _AttachmentSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Row(
      children: <Widget>[
        Icon(
          Icons.attach_file_outlined,
          size: 15,
          color: palette.onSurfaceMuted,
        ),
        SizedBox(width: m.spaceXs),
        Text(
          '$count file${count == 1 ? '' : 's'} attached to this visit',
          style: context.texts.labelSmall,
        ),
      ],
    );
  }
}

/// Where the patient went next. Easy to omit and often the most consequential
/// line in the record.
class _Disposition extends StatelessWidget {
  const _Disposition({required this.encounter});

  final Encounter encounter;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[
      if (encounter.disposition != null)
        (label: 'Outcome', value: encounter.disposition!.label),
      if (encounter.referredTo?.isNotEmpty ?? false)
        (label: 'Referred to', value: encounter.referredTo!),
      if (encounter.followUpDate != null)
        (label: 'Follow-up', value: Fmt.date(encounter.followUpDate)),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final row in rows)
          DetailRow(label: row.label, value: row.value, labelWidth: 88),
      ],
    );
  }
}

class _Signature extends StatelessWidget {
  const _Signature({required this.note});

  final ClinicalNote note;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final intact = note.verifyIntegrity();

    return Row(
      children: <Widget>[
        Icon(
          intact ? Icons.verified_outlined : Icons.gpp_bad_outlined,
          size: 15,
          color: intact ? palette.signedLock : palette.critical,
        ),
        SizedBox(width: m.spaceXs),
        Expanded(
          child: Text(
            intact
                ? 'Signed by ${note.signedBy ?? 'unknown'} · '
                    '${Fmt.dateTime(note.signedAt)}'
                : 'Integrity check failed — the stored text does not match '
                    'the signature',
            style: context.texts.labelSmall?.copyWith(
              color: intact ? palette.onSurfaceMuted : palette.critical,
            ),
          ),
        ),
      ],
    );
  }
}
