import '../../data/models/clinical_note.dart';

/// A skeleton that pre-fills the SOAP sections with prompts.
///
/// Templates exist to stop things being forgotten under time pressure, not to
/// produce identical notes. Every field is free text and fully editable — a
/// template that forces its own structure onto a consultation produces notes
/// that read well and say nothing.
class NoteTemplate {
  const NoteTemplate({
    required this.id,
    required this.name,
    required this.noteType,
    this.subjective = '',
    this.objective = '',
    this.assessment = '',
    this.plan = '',
  });

  final String id;
  final String name;
  final NoteType noteType;
  final String subjective;
  final String objective;
  final String assessment;
  final String plan;
}

abstract final class NoteTemplates {
  static const NoteTemplate blank = NoteTemplate(
    id: 'blank',
    name: 'Blank',
    noteType: NoteType.soap,
  );

  static const NoteTemplate generalConsult = NoteTemplate(
    id: 'general_consult',
    name: 'General consultation',
    noteType: NoteType.soap,
    subjective: 'Presenting complaint:\n'
        'Onset / duration:\n'
        'Associated symptoms:\n'
        'Relevant history:\n',
    objective: 'General appearance:\n'
        'Observations: (see recorded vitals)\n'
        'Examination:\n',
    assessment: 'Working diagnosis:\n'
        'Differential:\n',
    plan: 'Investigations:\n'
        'Treatment:\n'
        'Safety-netting advice:\n'
        'Follow-up:\n',
  );

  static const NoteTemplate followUp = NoteTemplate(
    id: 'follow_up',
    name: 'Follow-up review',
    noteType: NoteType.progress,
    subjective: 'Since last visit:\n'
        'Adherence to treatment:\n'
        'New symptoms:\n',
    objective: 'Observations: (see recorded vitals)\n'
        'Relevant examination:\n',
    assessment: 'Response to treatment:\n'
        'Current status:\n',
    plan: 'Continue / change treatment:\n'
        'Next review:\n',
  );

  static const NoteTemplate acutePresentation = NoteTemplate(
    id: 'acute',
    name: 'Acute presentation',
    noteType: NoteType.soap,
    subjective: 'Presenting complaint:\n'
        'Time of onset:\n'
        'Red-flag symptoms — chest pain / breathlessness / altered '
        'consciousness / bleeding:\n',
    objective: 'Airway:\n'
        'Breathing:\n'
        'Circulation:\n'
        'Disability (ACVPU, glucose):\n'
        'Exposure:\n',
    assessment: 'Impression:\n'
        'Early warning score and trend:\n',
    plan: 'Immediate treatment given:\n'
        'Escalation / referral:\n'
        'Reassessment interval:\n',
  );

  static const NoteTemplate antenatal = NoteTemplate(
    id: 'antenatal',
    name: 'Antenatal visit',
    noteType: NoteType.progress,
    subjective: 'Gestation:\n'
        'Fetal movements:\n'
        'Bleeding / discharge / contractions:\n'
        'Concerns:\n',
    objective: 'BP and urinalysis:\n'
        'Fundal height:\n'
        'Fetal heart rate:\n'
        'Presentation:\n',
    assessment: 'Pregnancy progressing normally / concerns:\n',
    plan: 'Supplements:\n'
        'Investigations:\n'
        'Next visit:\n'
        'Danger signs discussed:\n',
  );

  static const NoteTemplate procedure = NoteTemplate(
    id: 'procedure',
    name: 'Procedure',
    noteType: NoteType.procedure,
    subjective: 'Indication:\n'
        'Consent obtained: yes / no — discussed risks:\n',
    objective: 'Procedure performed:\n'
        'Anaesthesia:\n'
        'Findings:\n'
        'Complications: none / \n',
    assessment: 'Outcome:\n',
    plan: 'Aftercare instructions:\n'
        'Wound review / suture removal:\n',
  );

  static const List<NoteTemplate> all = <NoteTemplate>[
    blank,
    generalConsult,
    followUp,
    acutePresentation,
    antenatal,
    procedure,
  ];

  static NoteTemplate? byId(String? id) =>
      all.where((template) => template.id == id).firstOrNull;
}
