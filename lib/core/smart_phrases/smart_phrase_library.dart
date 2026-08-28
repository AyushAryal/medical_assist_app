import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/smart_phrase_record.dart';
import '../../features/patients/patient_picker_sheet.dart';
import '../app_bootstrap.dart';
import '../session/session_controller.dart';
import '../utils/formatters.dart';
import '../../data/repositories/clinical_repository.dart';
import 'patient_phrase_data.dart';
import 'smart_phrase.dart';

/// Assembles the smart-phrase vocabulary for a field: the code-resolved dynamic
/// macros first, then the user's text expansions from the database.
///
/// Three shapes of macro live here, in rising cleverness:
///
/// * **Values** — `\me`, `\today`, `\clinic`: resolve from session or clock.
/// * **A reference** — `\pat`: pick an exact patient, insert their name, and
///   carry the id so the assistant can act on it.
/// * **Record data** — `\vitals`, `\allergies`, `\meds`, `\problems`, `\hopi`:
///   read *this* patient's chart and paste the live facts. These use the patient
///   the screen is already about; where there is none (the assistant), they ask.
///
/// New dynamic macro → one entry in [_dynamicPhrases]. New text expansion → a
/// row a clinician adds in Settings.
SmartPhraseRegistry buildSmartPhraseRegistry(
  List<SmartPhraseRecord> textPhrases,
) {
  return SmartPhraseRegistry(<SmartPhrase>[
    ..._dynamicPhrases(),
    for (final record in textPhrases)
      SmartPhrase(
        trigger: record.trigger,
        title: record.title,
        description: _preview(record.body),
        icon: Icons.notes_outlined,
        resolve: (context, scope) async =>
            SmartPhraseValue(display: record.body, kind: 'text'),
      ),
  ]);
}

/// The macros that resolve at runtime and so cannot be data.
List<SmartPhrase> _dynamicPhrases() => <SmartPhrase>[
      SmartPhrase(
        trigger: 'pat',
        title: 'Patient',
        description: 'Pick an exact patient so the assistant is never guessing',
        icon: Icons.person_search_outlined,
        resolve: (context, scope) async {
          final patient = await PatientPickerSheet.show(context);
          if (patient == null) return null;
          return SmartPhraseValue(
            display: patient.displayName,
            kind: 'patient',
            payload: patient.id,
          );
        },
      ),
      _dataPhrase(
        trigger: 'vitals',
        title: 'Last vitals',
        description: "The patient's most recent observations",
        icon: Icons.monitor_heart_outlined,
        fetch: PatientPhraseData.vitals,
      ),
      _dataPhrase(
        trigger: 'allergies',
        title: 'Allergies',
        description: 'Known allergies and reactions',
        icon: Icons.warning_amber_outlined,
        fetch: PatientPhraseData.allergies,
      ),
      _dataPhrase(
        trigger: 'meds',
        title: 'Current medications',
        description: 'Active medications',
        icon: Icons.medication_outlined,
        fetch: PatientPhraseData.medications,
      ),
      _dataPhrase(
        trigger: 'problems',
        title: 'Problem list',
        description: 'Active problems',
        icon: Icons.assignment_outlined,
        fetch: PatientPhraseData.problems,
      ),
      _dataPhrase(
        trigger: 'hopi',
        title: 'History (last note)',
        description: 'History of the presenting illness from the last note',
        icon: Icons.history_edu_outlined,
        fetch: PatientPhraseData.historyOfPresentIllness,
      ),
      SmartPhrase(
        trigger: 'me',
        title: 'My name',
        description: 'Insert your signing name',
        icon: Icons.badge_outlined,
        resolve: (context, scope) async {
          final name = context.read<SessionController>().signatureName.trim();
          return name.isEmpty
              ? null
              : SmartPhraseValue(display: name, kind: 'text');
        },
      ),
      SmartPhrase(
        trigger: 'today',
        title: "Today's date",
        description: 'Insert the current date',
        icon: Icons.event_outlined,
        resolve: (context, scope) async =>
            SmartPhraseValue(display: Fmt.date(DateTime.now()), kind: 'text'),
      ),
      SmartPhrase(
        trigger: 'clinic',
        title: 'Current clinic',
        description: 'Insert the active clinic name',
        icon: Icons.local_hospital_outlined,
        resolve: (context, scope) async {
          final clinic = context.read<AppBootstrap>().session.activeClinic;
          return clinic == null
              ? null
              : SmartPhraseValue(display: clinic.name, kind: 'text');
        },
      ),
    ];

/// Builds a record-data macro that reads [fetch] for the scope's patient, or
/// asks for one when the screen is not already about a patient.
SmartPhrase _dataPhrase({
  required String trigger,
  required String title,
  required String description,
  required IconData icon,
  required Future<String> Function(ClinicalRepository, String) fetch,
}) {
  return SmartPhrase(
    trigger: trigger,
    title: title,
    description: description,
    icon: icon,
    resolve: (context, scope) async {
      final repository = context.read<ClinicalRepository>();
      var patientId = scope.patientId;
      if (patientId == null) {
        final picked = await PatientPickerSheet.show(context);
        patientId = picked?.id;
      }
      if (patientId == null) return null;
      final text = await fetch(repository, patientId);
      return SmartPhraseValue(display: text, kind: 'text');
    },
  );
}

/// A one-line preview of a phrase body for the menu.
String _preview(String body) {
  final firstLine = body.split('\n').first.trim();
  return firstLine.length <= 60 ? firstLine : '${firstLine.substring(0, 57)}…';
}
