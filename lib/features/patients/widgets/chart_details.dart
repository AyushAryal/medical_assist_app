import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/attachment.dart';
import '../../../data/models/patient.dart';
import '../patient_chart_controller.dart';
import '../visit_record_view.dart';

class Contact extends StatelessWidget {
  const Contact({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Contact',
      leading: const Icon(Icons.contact_phone_outlined, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ContactRow(
            phone: patient.phone,
            altPhone: patient.altPhone,
            patientName: patient.displayName,
          ),
          if (patient.nextOfKinName != null) ...<Widget>[
            SectionCard.divider(context),
            Text(
              'Next of kin — ${patient.nextOfKinName}'
              '${patient.nextOfKinRelation == null ? '' : ' (${patient.nextOfKinRelation})'}',
              style: context.texts.labelMedium,
            ),
            SizedBox(height: context.metrics.spaceSm),
            ContactRow(
              phone: patient.nextOfKinPhone,
              patientName: patient.nextOfKinName!,
            ),
          ],
        ],
      ),
    );
  }
}

/// The identity facts that drive dosing and reference ranges.
///
/// Sex at birth and gender identity are shown separately because they do
/// different jobs: the first selects reference ranges and drug dosing, the
/// second is how the patient is addressed. Collapsing them loses one or
/// insults the patient.
class Demographics extends StatelessWidget {
  const Demographics({super.key, required this.patient, required this.chart});

  final Patient patient;
  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final age = chart.age;

    return SectionCard(
      title: 'Patient details',
      leading: const Icon(Icons.badge_outlined, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DetailRow(label: 'MRN', value: patient.mrn),
          DetailRow(
            label: 'Age',
            value: age == null
                ? 'Not recorded'
                : patient.dobIsEstimated
                    ? '~${age.label} (approximate)'
                    : age.label,
          ),
          DetailRow(
            label: 'Date of birth',
            value: patient.dateOfBirth == null
                ? 'Not recorded'
                : patient.dobIsEstimated
                    // Never print a birthday the record cannot support: an
                    // approximate age is stored as 1 January.
                    ? 'Year ${patient.dateOfBirth!.year}, estimated'
                    : Fmt.date(patient.dateOfBirth),
          ),
          DetailRow(label: 'Sex at birth', value: patient.sexAtBirth.label),
          if (patient.genderIdentity?.isNotEmpty ?? false)
            DetailRow(label: 'Gender', value: patient.genderIdentity!),
          if (patient.bloodGroup?.isNotEmpty ?? false)
            DetailRow(label: 'Blood group', value: patient.bloodGroup!),
          if (patient.nationalId?.isNotEmpty ?? false)
            DetailRow(label: 'National ID', value: patient.nationalId!),
          if (patient.occupation?.isNotEmpty ?? false)
            DetailRow(label: 'Occupation', value: patient.occupation!),
          if (patient.addressLine?.isNotEmpty ?? false)
            DetailRow(
              label: 'Address',
              value: <String>[
                patient.addressLine!,
                if (patient.city?.isNotEmpty ?? false) patient.city!,
                if (patient.district?.isNotEmpty ?? false) patient.district!,
              ].join(', '),
            ),
          if (patient.isDeceased)
            DetailRow(
              label: 'Deceased',
              value: Fmt.date(patient.deceasedDate),
            ),
        ],
      ),
    );
  }
}

/// The last visit, in full, on the summary tab.
///
/// "What happened last time" is the question asked before almost every
/// consultation, and it should not cost a tab change to answer.
class LastVisit extends StatelessWidget {
  const LastVisit({super.key, required this.chart});

  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final visit = chart.visits.firstOrNull;
    if (visit == null) return const SizedBox.shrink();

    return SectionCard(
      title: 'Last visit',
      subtitle: Fmt.relative(visit.encounter.startedAt),
      leading: const Icon(Icons.history_outlined, size: 20),
      child: VisitRecordView(
        visit: visit,
        patient: chart.patient!,
        age: chart.age,
        dense: true,
      ),
    );
  }
}

/// Everything attached to this patient, newest first.
class FileList extends StatelessWidget {
  const FileList({super.key, required this.attachments});

  final List<Attachment> attachments;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return SectionCard(
      title: 'Files',
      subtitle: '${attachments.length} item'
          '${attachments.length == 1 ? '' : 's'}',
      leading: const Icon(Icons.folder_outlined, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final attachment in attachments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                switch (attachment.kind) {
                  AttachmentKind.photo => Icons.image_outlined,
                  AttachmentKind.document => Icons.description_outlined,
                  AttachmentKind.audio => Icons.graphic_eq,
                  AttachmentKind.video => Icons.videocam_outlined,
                },
                color: palette.onSurfaceMuted,
              ),
              title: Text(attachment.caption ?? attachment.fileName),
              subtitle: Text(
                <String>[
                  Fmt.date(attachment.capturedAt ?? attachment.createdAt),
                  // Both return an empty string rather than null when the
                  // underlying value is missing.
                  attachment.sizeLabel,
                  attachment.durationLabel,
                  if (attachment.bodySite?.isNotEmpty ?? false)
                    attachment.bodySite!,
                ].where((part) => part.isNotEmpty).join(' · '),
              ),
            ),
          SizedBox(height: m.spaceXs),
          Text(
            'Files are opened from the visit they belong to, where the note '
            'that explains them is alongside.',
            style: context.texts.labelSmall,
          ),
        ],
      ),
    );
  }
}
