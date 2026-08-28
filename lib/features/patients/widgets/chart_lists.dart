import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/allergy.dart';
import '../../../data/models/patient.dart';
import '../chart_entry_sheets.dart';
import '../patient_chart_controller.dart';

class ProblemList extends StatelessWidget {
  const ProblemList({super.key, required this.chart});

  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final active = chart.activeProblems;
    final resolved = chart.problems.where((p) => !p.isActive).length;

    return SectionCard(
      title: 'Problem list',
      subtitle: resolved == 0 ? null : '$resolved resolved',
      leading: const Icon(Icons.checklist_outlined, size: 20),
      trailing: IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Add problem',
        onPressed: () => ProblemSheet.show(context, chart),
      ),
      child: active.isEmpty
          ? const EmptyState(
              icon: Icons.checklist_outlined,
              title: 'No active problems',
              message: 'Add a diagnosis to build the problem list.',
              compact: true,
            )
          : Column(
              children: active.map((problem) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(problem.display),
                  subtitle: Text(
                    <String>[
                      if (problem.codeLabel.isNotEmpty) problem.codeLabel,
                      if (problem.onsetDate != null)
                        'since ${Fmt.date(problem.onsetDate)}',
                    ].join(' · '),
                  ),
                  trailing: problem.isChronic
                      ? const StatusPill(
                          label: 'Chronic',
                          tone: PillTone.info,
                          dense: true,
                        )
                      : null,
                );
              }).toList(),
            ),
    );
  }
}

class MedicationList extends StatelessWidget {
  const MedicationList({super.key, required this.chart});

  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final active = chart.activeMedications;

    return SectionCard(
      title: 'Current medications',
      leading: const Icon(Icons.medication_outlined, size: 20),
      trailing: IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Add medication',
        onPressed: () => MedicationSheet.show(context, chart),
      ),
      child: active.isEmpty
          ? const EmptyState(
              icon: Icons.medication_outlined,
              title: 'No current medications',
              compact: true,
            )
          : Column(
              children: active.map((medication) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(medication.sig),
                  subtitle: medication.indication == null
                      ? null
                      : Text('for ${medication.indication}'),
                );
              }).toList(),
            ),
    );
  }
}

class AllergyList extends StatelessWidget {
  const AllergyList({super.key, required this.chart});

  final PatientChartController chart;

  @override
  Widget build(BuildContext context) {
    final active = chart.allergies.where((a) => a.isActive).toList();

    return SectionCard(
      title: 'Allergies',
      leading: const Icon(Icons.warning_amber_outlined, size: 20),
      trailing: IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Add allergy',
        onPressed: () => AllergySheet.show(context, chart),
      ),
      child: active.isEmpty
          ? EmptyState(
              icon: Icons.info_outline,
              title: chart.patient!.allergyStatus.label,
              message: chart.patient!.allergyStatus == AllergyStatus.unknown
                  ? 'Ask the patient and record the answer either way.'
                  : null,
              compact: true,
            )
          : Column(
              children: active.map((allergy) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(allergy.substance),
                  subtitle: Text(
                    <String>[
                      allergy.category.label,
                      if (allergy.reaction?.isNotEmpty == true)
                        allergy.reaction!,
                    ].join(' · '),
                  ),
                  trailing: StatusPill(
                    label: allergy.severity.label,
                    tone: allergy.severity.isHighRisk
                        ? PillTone.critical
                        : PillTone.caution,
                    dense: true,
                  ),
                );
              }).toList(),
            ),
    );
  }
}
