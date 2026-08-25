import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/session/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ids.dart';
import '../../data/models/attachment.dart';
import '../../data/models/clinical_note.dart';
import '../../data/models/encounter.dart';
import '../../data/models/medication.dart';
import '../../data/models/patient.dart';
import '../../data/models/problem.dart';
import '../../data/repositories/clinical_repository.dart';
import '../../core/app_bootstrap.dart';
import '../../clinical/insights/note_intelligence.dart';
import '../attachments/attachment_strip.dart';
import '../attachments/field_attach_bar.dart';
import 'amend_note_sheet.dart';
import 'dictation_sheet.dart';
import 'draft_review_screen.dart';
import 'patient_instructions_sheet.dart';
import '../../data/services/assist/note_drafting.dart';
import 'template_picker_sheet.dart';

/// The SOAP note editor.
///
/// Three behaviours matter more than anything cosmetic here:
///
/// * **Autosave.** Consultations get interrupted. Nothing is ever lost to a
///   missed "save" tap.
/// * **Locking.** Once signed the fields become read-only and corrections go
///   through the amendment path, which appends rather than overwrites.
/// * **Copy forward.** Pulling the previous assessment and plan into a
///   follow-up is the single biggest time saver in routine outpatient work —
///   provided it is explicit, visible, and never automatic.
/// * **Nothing writes itself.** Templates, dictation and the suggestion strip
///   all propose; the clinician disposes. Autosave persists what is in the
///   fields, and what is in the fields only ever got there by a deliberate
///   action.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.encounterId});

  final String encounterId;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final TextEditingController _subjective = TextEditingController();
  final TextEditingController _objective = TextEditingController();
  final TextEditingController _assessment = TextEditingController();
  final TextEditingController _plan = TextEditingController();

  /// The rough draft: a whole consultation dictated in one go.
  ///
  /// The four SOAP boxes are where a note *ends up*; nobody dictates in that
  /// order. This is the box people actually talk into, and sorting out of it
  /// is what the model is for — which is why the model's button lives here
  /// and not on Subjective, where it used to sit asking clinicians to dump
  /// everything into one section they would then have to un-dump.
  final TextEditingController _working = TextEditingController();

  Timer? _autosave;
  ClinicalNote? _note;
  Encounter? _encounter;
  Patient? _patient;
  List<NoteAmendment> _amendments = const <NoteAmendment>[];
  List<Attachment> _attachments = const <Attachment>[];
  Map<String, String> _attachmentPaths = const <String, String>{};
  bool _loading = true;
  bool _dirty = false;
  DateTime? _savedAt;

  /// Snapshot taken immediately before a template or copy-forward writes into
  /// the fields, so the change can be undone in one tap. Autosave means the
  /// write has already reached the database by the time the clinician realises
  /// it was wrong, and "undo" that only works before the next save is not undo.
  Map<String, String>? _undoSnapshot;

  /// Structured entries the note text suggests. Recomputed on a debounce
  /// rather than per keystroke — the matching is fast, but rebuilding the
  /// strip under the cursor while someone is mid-word is distracting.
  List<ExtractedTerm> _suggestions = const <ExtractedTerm>[];
  Timer? _suggestionDebounce;
  final Set<String> _dismissedSuggestions = <String>{};

  /// The recording currently being turned into text, if any.
  String? _transcribingId;

  /// True while the on-device model is drafting. One flag for both tasks: a
  /// 1B model answers in seconds, and two overlapping inferences on tablet
  /// CPUs would starve each other.
  bool _drafting = false;

  /// Section key to the exact text the model put there, kept so a section can
  /// still say it holds generated text — and stop saying it the moment a
  /// clinician edits a character of it. Comparing the whole field is what
  /// makes that survive undo, autosave and a reload without a listener to get
  /// wrong.
  final Map<String, String> _aiText = <String, String>{};

  /// The pending "you can undo that" message, and the timer that retires it.
  ///
  /// Shown as a banner rather than a SnackBar. A SnackBar looked right and
  /// behaved wrongly: Flutter deliberately makes them persist indefinitely
  /// when an accessibility service is running, so on plenty of real devices
  /// the message simply never went away. Owning the timer makes the behaviour
  /// the same everywhere.
  String? _undoMessage;
  Timer? _undoTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    for (final controller in _controllers) {
      controller.addListener(_onChanged);
    }
  }

  List<TextEditingController> get _controllers =>
      <TextEditingController>[
        _working,
        _subjective,
        _objective,
        _assessment,
        _plan,
      ];

  @override
  void dispose() {
    _autosave?.cancel();
    _suggestionDebounce?.cancel();
    _undoTimer?.cancel();
    // Flush synchronously-known edits before the widget goes away.
    if (_dirty) unawaited(_save());
    for (final controller in _controllers) {
      controller.removeListener(_onChanged);
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repository = context.read<ClinicalRepository>();
    final encounter = await repository.encounters.byId(widget.encounterId);
    if (encounter == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final note = await repository.noteForEncounter(encounter);
    final patient = await repository.patients.byId(encounter.patientId);
    final amendments = await repository.notes.amendments(note.id);
    final attachments = await repository.attachments.forOwner(
      AttachmentOwner.note,
      note.id,
    );
    // Stored paths are relative; resolve them once so the inline players and
    // thumbnails do not each hit the filesystem.
    final paths = <String, String>{};
    for (final attachment in attachments) {
      paths[attachment.id] =
          await repository.attachmentFiles.absolutePath(attachment);
    }

    if (!mounted) return;
    _working.text = note.workingNotes ?? '';
    _subjective.text = note.subjective ?? '';
    _objective.text = note.objective ?? '';
    _assessment.text = note.assessment ?? '';
    _plan.text = note.plan ?? '';

    setState(() {
      _encounter = encounter;
      _note = note;
      _patient = patient;
      _amendments = amendments;
      _attachments = attachments;
      _attachmentPaths = paths;
      _loading = false;
      _dirty = false;
    });
  }

  /// Debounced so a burst of typing produces one write, not one per character.
  void _onChanged() {
    if (_note?.isLocked ?? true) return;
    _dirty = true;
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 900), _save);

    _suggestionDebounce?.cancel();
    _suggestionDebounce =
        Timer(const Duration(milliseconds: 1200), _refreshSuggestions);
  }

  void _refreshSuggestions() {
    if (!mounted) return;
    final assist = context.read<AppBootstrap>().assist;
    final text = <String>[
      _subjective.text,
      _objective.text,
      _assessment.text,
      _plan.text,
    ].join('\n');

    setState(() {
      _suggestions = assist
          .suggestionsFrom(text)
          .where((t) => !_dismissedSuggestions.contains(_suggestionKey(t)))
          .toList();
    });
  }

  static String _suggestionKey(ExtractedTerm term) =>
      '${term.kind.name}:${term.text}';

  Future<void> _save() async {
    final note = _note;
    if (note == null || note.isLocked || !_dirty) return;

    final updated = note.copyWith(
      subjective: _subjective.text,
      objective: _objective.text,
      assessment: _assessment.text,
      plan: _plan.text,
      // Saved like everything else: dictation that survives an interruption
      // only because it was autosaved is the entire point of a scratch field.
      workingNotes: _working.text,
    );

    await context.read<ClinicalRepository>().saveNoteDraft(updated);
    if (!mounted) return;
    setState(() {
      _note = updated;
      _dirty = false;
      _savedAt = DateTime.now();
    });
  }

  Map<String, TextEditingController> get _fields =>
      <String, TextEditingController>{
        'subjective': _subjective,
        'objective': _objective,
        'assessment': _assessment,
        'plan': _plan,
      };

  static const Map<String, String> _fieldLabels = <String, String>{
    'subjective': 'Subjective',
    'objective': 'Objective',
    'assessment': 'Assessment',
    'plan': 'Plan',
  };

  /// Records the current text so the next bulk change can be reversed.
  void _markUndoPoint() {
    _undoSnapshot = <String, String>{
      for (final entry in _fields.entries) entry.key: entry.value.text,
    };
  }

  void _undo() {
    _dismissUndo();
    final snapshot = _undoSnapshot;
    if (snapshot == null) return;
    setState(() {
      for (final entry in _fields.entries) {
        entry.value.text = snapshot[entry.key] ?? '';
      }
      _undoSnapshot = null;
    });
    _onChanged();
  }

  void _offerUndo(String message) {
    _undoTimer?.cancel();
    setState(() => _undoMessage = message);
    _undoTimer = Timer(const Duration(seconds: 8), _dismissUndo);
  }

  void _dismissUndo() {
    _undoTimer?.cancel();
    _undoTimer = null;
    if (mounted) setState(() => _undoMessage = null);
  }

  /// Applies a template, having shown the clinician exactly what it will do.
  ///
  /// The old behaviour silently skipped any section that already had text.
  /// Protecting written text is right; doing it invisibly is not — the
  /// clinician could not tell a protected section from a template that simply
  /// had nothing for it. Now the sheet shows both, defaults to protecting, and
  /// the result is undoable.
  Future<void> _applyTemplate() async {
    final application = await TemplatePickerSheet.show(
      context,
      sections: <TemplateSection>[
        for (final entry in _fields.entries)
          (
            key: entry.key,
            label: _fieldLabels[entry.key]!,
            current: entry.value.text,
          ),
      ],
    );
    if (application == null || !mounted) return;

    _markUndoPoint();
    final written = <String>[];

    setState(() {
      for (final entry in _fields.entries) {
        if (!application.writesTo(entry.key)) continue;
        entry.value.text = switch (entry.key) {
          'subjective' => application.template.subjective,
          'objective' => application.template.objective,
          'assessment' => application.template.assessment,
          _ => application.template.plan,
        };
        written.add(_fieldLabels[entry.key]!);
      }
      _note = _note?.copyWith(
        templateId: application.template.id,
        noteType: application.template.noteType,
      );
    });
    _onChanged();

    if (!mounted) return;
    _offerUndo(
      written.isEmpty
          ? 'Note type set to ${application.template.noteType.label}. '
              'Your text was left alone.'
          : 'Inserted into ${written.join(', ')}.',
    );
  }

  /// Records dictation for one section, and offers its transcript.
  ///
  /// The audio is attached whatever happens to the text. A transcript is an
  /// interpretation; the recording is the primary evidence, and it is what the
  /// record falls back on when a transcript is disputed.
  Future<void> _dictate(String sectionKey) async {
    final label = _fieldLabels[sectionKey]!;
    final outcome = await DictationSheet.show(context, sectionLabel: label);
    if (outcome == null || !mounted) return;

    await _attach(
      file: outcome.audio.file,
      kind: AttachmentKind.audio,
      section: label,
      mimeType: 'audio/wav',
      durationMs: outcome.audio.duration.inMilliseconds,
    );

    // The untrimmed capture, when the operator chose to keep it. Attached as a
    // second file and captioned as such, so a listener can tell at a glance
    // which one is the record and which one is the raw evidence behind it.
    if (outcome.audio.originalFile case final original?) {
      await _attach(
        file: original,
        kind: AttachmentKind.audio,
        section: '$label · original',
        mimeType: 'audio/wav',
        durationMs: outcome.audio.originalDuration.inMilliseconds,
      );
    }

    if (!outcome.hasTranscript || !mounted) return;

    _markUndoPoint();
    final controller = _fields[sectionKey]!;
    final existing = controller.text.trimRight();
    setState(() {
      controller.text = existing.isEmpty
          ? outcome.transcript!.trim()
          : '$existing\n${outcome.transcript!.trim()}';
    });
    _onChanged();

    if (!mounted) return;
    _offerUndo('Transcript added to $label. Check it before signing.');
  }

  /// Turns an already-attached recording into text.
  ///
  /// The gap this closes: dictation captured before a speech model was
  /// installed — or on a build that predates transcription — was audio for
  /// good, and the only way to find out what was said was to listen to all of
  /// it. Anything already in the record should be reachable by the tools added
  /// since, not just what is captured from now on.
  Future<void> _transcribeExisting(Attachment attachment, String section) async {
    final bootstrap = context.read<AppBootstrap>();
    final messenger = ScaffoldMessenger.of(context);
    final path = _attachmentPaths[attachment.id];
    if (path == null) return;

    setState(() => _transcribingId = attachment.id);
    try {
      final availability = await bootstrap.transcription.availability();
      if (!availability.isReady) {
        messenger.showSnackBar(
          SnackBar(content: Text(availability.reason ?? 'Not available.')),
        );
        return;
      }

      final result = await bootstrap.transcription.transcribe(File(path));
      if (!mounted) return;

      if (result.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Nothing recognisable in that recording.'),
          ),
        );
        return;
      }

      final key = _fieldLabels.entries
          .firstWhere(
            (entry) => entry.value == section,
            orElse: () => const MapEntry<String, String>(
              'subjective',
              'Subjective',
            ),
          )
          .key;

      _markUndoPoint();
      final controller = _fields[key]!;
      final existing = controller.text.trimRight();
      setState(() {
        controller.text = existing.isEmpty
            ? result.text.trim()
            : '$existing\n${result.text.trim()}';
      });
      _onChanged();
      if (mounted) {
        _offerUndo('Transcript added to $section. Check it before signing.');
      }
    } on FormatException {
      // Recordings made before the current pipeline are compressed AAC, and
      // there is no decoder available here. Saying which files can be
      // transcribed beats a generic failure the user cannot act on.
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'This recording is in a compressed format that cannot be '
            'transcribed on the device. Recordings made with the current '
            'version can be.',
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not transcribe: $error')),
      );
    } finally {
      if (mounted) setState(() => _transcribingId = null);
    }
  }

  /// Accepts a suggestion by writing it to the structured chart.
  ///
  /// Every path here goes through the repository, so an entry created from a
  /// suggestion is audited exactly like one typed by hand — there is no
  /// second-class way into the record.
  Future<void> _acceptSuggestion(ExtractedTerm term) async {
    final patient = _patient;
    if (patient == null) return;

    final repository = context.read<ClinicalRepository>();
    final now = DateTime.now();

    switch (term.kind) {
      case ExtractedTermKind.problem:
        await repository.patients.addProblem(
          Problem(
            id: newId(),
            patientId: patient.id,
            display: term.text,
            onsetDate: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
      case ExtractedTermKind.medication:
        // "Amlodipine 5mg" arrives as one string; the chart holds the drug and
        // its dose separately so the medication list stays sortable and
        // searchable by drug.
        final split = RegExp(r'^(.*?)\s+(\d.*)$').firstMatch(term.text);
        await repository.patients.addMedication(
          Medication(
            id: newId(),
            patientId: patient.id,
            name: (split?.group(1) ?? term.text).trim(),
            dose: split?.group(2)?.trim(),
            startedOn: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
      case ExtractedTermKind.allergy:
        // Deliberately not written straight through. A wrongly recorded
        // allergy removes a treatment option, usually permanently, because
        // nobody downstream ever feels safe deleting one. Severity and
        // reaction have to be asked, so this opens the full form instead.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Add "${term.text}" from the chart, where severity and reaction '
              'are recorded with it.',
            ),
          ),
        );
        return;
      case ExtractedTermKind.followUp:
      case ExtractedTermKind.redFlag:
        return;
    }

    if (!mounted) return;
    setState(() {
      _dismissedSuggestions.add(_suggestionKey(term));
      _suggestions =
          _suggestions.where((t) => t != term).toList(growable: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${term.kind.label} added: ${term.text}')),
    );
  }

  void _dismissSuggestion(ExtractedTerm term) {
    setState(() {
      _dismissedSuggestions.add(_suggestionKey(term));
      _suggestions =
          _suggestions.where((t) => t != term).toList(growable: false);
    });
  }

  /// Brings the previous signed note's assessment and plan into this one,
  /// clearly labelled with its date so it never reads as fresh observation.
  Future<void> _copyForward() async {
    final note = _note;
    final encounter = _encounter;
    if (note == null || encounter == null) return;

    final repository = context.read<ClinicalRepository>();
    final previous = await repository.notes.previousSigned(
      encounter.patientId,
      excludingEncounterId: encounter.id,
    );

    if (!mounted) return;
    if (previous == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous signed note to copy from.')),
      );
      return;
    }

    final stamp = Fmt.date(previous.signedAt ?? previous.createdAt);
    _markUndoPoint();
    setState(() {
      if (previous.assessment?.trim().isNotEmpty == true) {
        _assessment.text = <String>[
          if (_assessment.text.trim().isNotEmpty) _assessment.text.trimRight(),
          'Carried forward from $stamp:',
          previous.assessment!.trim(),
        ].join('\n');
      }
      if (previous.plan?.trim().isNotEmpty == true) {
        _plan.text = <String>[
          if (_plan.text.trim().isNotEmpty) _plan.text.trimRight(),
          'Carried forward from $stamp:',
          previous.plan!.trim(),
        ].join('\n');
      }
    });
    _onChanged();

    if (!mounted) return;
    _offerUndo('Copied assessment and plan from $stamp.');
  }

  Future<void> _sign() async {
    await _save();
    if (!mounted) return;

    final note = _note;
    if (note == null) return;

    if (note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An empty note cannot be signed.')),
      );
      return;
    }

    // Anything still in the working notes is about to stop existing: it is
    // not part of the signed record and the signature clears it. Saying so is
    // the difference between a scratch pad and a place dictation goes to die.
    final unsorted = _working.text.trim();
    final generated = _fields.keys.where(_isGenerated).toList();

    final session = context.read<SessionController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign this note?'),
        content: Text(
          <String>[
            if (unsorted.isNotEmpty)
              'Your working notes still hold '
                  '${unsorted.split(RegExp(r'\s+')).length} words that are '
                  'not in any section. They are not part of the signed record '
                  'and will be cleared.',
            if (generated.isNotEmpty)
              'You have not edited the text the model put into '
                  '${generated.map((k) => _fieldLabels[k]!).join(' and ')} — '
                  'read it once more before it becomes the record.',
            'The note becomes the final record and can no longer be edited. '
                'Later corrections are added as amendments, which stay '
                'visible alongside the original.',
            'Signing as ${session.signatureName}.',
          ].join('\n\n'),
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

    // Scratch does not survive signing: the record is the four sections.
    if (unsorted.isNotEmpty) {
      await context
          .read<ClinicalRepository>()
          .saveNoteDraft(note.copyWith(clearWorkingNotes: true));
    }
    if (!mounted) return;
    await context
        .read<ClinicalRepository>()
        .signNote(note, signedBy: session.signatureName);
    _aiText.clear();
    await _load();
  }

  /// Attaches a captured file to the note and to the section it came from.
  ///
  /// The section is recorded in the caption so the strip can show each file
  /// under the field it belongs to — a wound photo taken while writing the
  /// examination belongs next to Objective, not in a general pile.
  Future<void> _attach({
    required File file,
    required AttachmentKind kind,
    required String section,
    String? mimeType,
    int? durationMs,
    String? bodySite,
  }) async {
    final note = _note;
    final patient = _patient;
    if (note == null || patient == null) return;

    final repository = context.read<ClinicalRepository>();
    await repository.attach(
      source: file,
      patientId: patient.id,
      ownerType: AttachmentOwner.note,
      ownerId: note.id,
      kind: kind,
      mimeType: mimeType,
      caption: '$section · ${kind.label}',
      bodySite: bodySite,
      durationMs: durationMs,
      createdBy: context.read<SessionController>().signatureName,
    );
    await _load();
  }

  Future<void> _removeAttachment(Attachment attachment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove attachment?'),
        content: const Text(
          'The file is deleted from this device. The record of it having been '
          'added remains in the access log.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<ClinicalRepository>().removeAttachment(attachment);
    await _load();
  }

  List<Attachment> _forSection(String section) => _attachments
      .where((a) => (a.caption ?? '').startsWith(section))
      .toList(growable: false);

  /// Anything captured before sections existed, or from elsewhere.
  List<Attachment> get _unsectioned => _attachments
      .where((a) => !_sections.any((s) => (a.caption ?? '').startsWith(s)))
      .toList(growable: false);

  static const List<String> _sections = <String>[
    'Subjective',
    'Objective',
    'Assessment',
    'Plan',
  ];

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final note = _note;
    final patient = _patient;
    if (note == null || patient == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(),
        body: const Center(child: Text('Note not found')),
      );
    }

    final m = context.metrics;
    final isLocked = note.isLocked;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _dirty) unawaited(_save());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(note.noteType.label),
          actions: <Widget>[
            Padding(
              padding: EdgeInsets.only(right: m.spaceMd),
              child: Center(
                child: StatusPill(
                  label: note.status.label,
                  tone: isLocked ? PillTone.normal : PillTone.caution,
                  icon: isLocked ? Icons.lock_outline : null,
                  dense: true,
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_undoMessage case final message?)
                _UndoBanner(
                  message: message,
                  onUndo: _undo,
                  onDismiss: _dismissUndo,
                ),
              Padding(
            padding: EdgeInsets.all(m.spaceLg),
            child: isLocked
                ? OutlinedButton.icon(
                    onPressed: () async {
                      await AmendNoteSheet.show(context, note: note);
                      await _load();
                    },
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Add amendment'),
                  )
                : FilledButton.icon(
                    onPressed: _sign,
                    icon: const Icon(Icons.draw_outlined),
                    label: const Text('Sign note'),
                  ),
              ),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            PatientIdentityBar(patient: patient),
            if (isLocked) _SignatureBar(note: note),
            if (!isLocked)
              _NoteToolbar(
                onTemplate: _applyTemplate,
                onCopyForward: _copyForward,
                onDictate: () => _dictate(_focusedSection),
              ),
            Expanded(
              child: ContentWidth.columns(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(m.spaceLg),
                  child: SplitColumns(
                    primaryFlex: 3,
                    secondaryFlex: 2,
                    primary: <Widget>[
                      if (!isLocked)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: context.metrics.spaceMd,
                          ),
                          child: _WorkingNotesCard(
                            controller: _working,
                            hasModel: context
                                .watch<AppBootstrap>()
                                .assistModelActive,
                            isDrafting: _drafting,
                            onSort: _sortWorkingNotes,
                            onDictate: () => _dictateWorking(),
                          ),
                        ),
                      for (final key in _fields.keys) _soapField(key, isLocked),
                    ],
                    secondary: <Widget>[
                      if (!isLocked && _suggestions.isNotEmpty)
                        _SuggestionPanel(
                          suggestions: _suggestions,
                          onAccept: _acceptSuggestion,
                          onDismiss: _dismissSuggestion,
                        ),
                      if (_unsectioned.isNotEmpty)
                        SectionCard(
                          title: 'Other attachments',
                          leading:
                              const Icon(Icons.attach_file_outlined, size: 20),
                          child: AttachmentStrip(
                            attachments: _unsectioned,
                            paths: _attachmentPaths,
                            onDelete: isLocked ? null : _removeAttachment,
                          ),
                        ),
                      if (_amendments.isNotEmpty)
                        _AmendmentList(amendments: _amendments),
                      if (!isLocked)
                        _SaveStatus(dirty: _dirty, savedAt: _savedAt),
                      SizedBox(height: m.space2xl),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Which section dictation lands in when started from the toolbar.
  ///
  /// Each field also has its own microphone; the toolbar exists because a
  /// clinician who has just finished examining a patient wants to start
  /// talking without first deciding where the words go. Subjective is the
  /// right default — it is where a consultation starts and where the longest
  /// free text goes.
  String get _focusedSection {
    for (final entry in _fields.entries) {
      if (entry.value.text.trim().isEmpty) return entry.key;
    }
    return 'subjective';
  }

  /// Dictation straight into the working notes.
  ///
  /// The same recorder, the same on-device transcription and the same
  /// attachment rules as a section dictation — the audio is filed as evidence
  /// whatever happens to the text, because the recording is what the record
  /// falls back on when a transcript is disputed.
  Future<void> _dictateWorking() async {
    final outcome = await DictationSheet.show(
      context,
      sectionLabel: 'Working notes',
    );
    if (outcome == null || !mounted) return;

    await _attach(
      file: outcome.audio.file,
      kind: AttachmentKind.audio,
      section: 'Working notes',
      mimeType: 'audio/wav',
      durationMs: outcome.audio.duration.inMilliseconds,
    );
    if (outcome.audio.originalFile case final original?) {
      await _attach(
        file: original,
        kind: AttachmentKind.audio,
        section: 'Working notes · original',
        mimeType: 'audio/wav',
        durationMs: outcome.audio.originalDuration.inMilliseconds,
      );
    }

    if (!outcome.hasTranscript || !mounted) return;
    _markUndoPoint();
    final existing = _working.text.trimRight();
    setState(() {
      _working.text = existing.isEmpty
          ? outcome.transcript!.trim()
          : '$existing\n${outcome.transcript!.trim()}';
    });
    _onChanged();
    if (mounted) _offerUndo('Transcript added to the working notes.');
  }

  /// Sorts the working notes into the four sections, via the on-device model.
  ///
  /// Reads only the working notes, and empties them of whatever was accepted.
  /// That is the whole shape of the feature: dictate a consultation into one
  /// box, have it distributed, and be left with the remainder — so what did
  /// *not* get sorted stays visible rather than being silently dropped.
  Future<void> _sortWorkingNotes() async {
    final engine = context.read<AppBootstrap>().assistEngine;
    final messenger = ScaffoldMessenger.of(context);
    if (engine == null || _drafting) return;

    final source = _working.text.trim();
    setState(() => _drafting = true);
    try {
      final draft = await NoteDrafting.sortIntoSoap(engine, source);
      if (!mounted) return;

      final accepted = await DraftReviewScreen.show(
        context,
        draft: draft,
        current: <String, String>{
          for (final entry in _fields.entries) entry.key: entry.value.text,
        },
        source: source,
      );
      if (accepted == null || accepted.isEmpty || !mounted) return;

      _markUndoPoint();
      setState(() {
        for (final entry in accepted.entries) {
          final field = _fields[entry.key]!;
          final existing = field.text.trimRight();
          field.text = existing.isEmpty
              ? entry.value
              : '$existing\n${entry.value}';
          // Remembered exactly, so the section can say it holds generated
          // text until the moment a clinician edits a character of it.
          _aiText[entry.key] = field.text;
        }
        // Only what was accepted leaves the working notes. A discarded
        // section's words stay in the box, because they still have not been
        // recorded anywhere.
        final kept = accepted.values.join(' ');
        _working.text = _remainderOf(source, kept);
      });
      _onChanged();
      _offerUndo(
        'Sorted into ${accepted.length} '
        '${accepted.length == 1 ? 'section' : 'sections'}. '
        'Generated text stays marked until you edit it.',
      );
    } on DraftRefused catch (refusal) {
      messenger.showSnackBar(SnackBar(content: Text(refusal.reason)));
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  /// What is left of the working notes once the sorted sentences are removed.
  ///
  /// Sentence-wise rather than by string subtraction: the sort rearranges, so
  /// the accepted text is the same sentences in a different order, and
  /// matching whole sentences is what survives that. A sentence that cannot be
  /// matched stays — leaving something behind is a nuisance, dropping
  /// something a clinician said is a lost record.
  static String _remainderOf(String source, String kept) {
    final placed = kept
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();

    final remainder = source
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((sentence) => !placed.contains(sentence.trim().toLowerCase()))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty);

    return remainder.join(' ');
  }

  /// Rewords the plan as instructions for the patient, via the model.
  Future<void> _explainForPatient() async {
    final engine = context.read<AppBootstrap>().assistEngine;
    final messenger = ScaffoldMessenger.of(context);
    if (engine == null || _drafting) return;

    final plan = _plan.text.trim();
    setState(() => _drafting = true);
    try {
      final draft = await NoteDrafting.patientInstructions(engine, plan);
      if (!mounted) return;
      final action = await PatientInstructionsSheet.show(
        context,
        draft: draft,
        plan: plan,
      );
      if (!mounted) return;

      switch (action) {
        case InstructionsAction.appended:
          _markUndoPoint();
          setState(() {
            _plan.text = '${_plan.text.trimRight()}\n\n'
                'For the patient:\n${draft.text}';
            _aiText['plan'] = _plan.text;
          });
          _onChanged();
          _offerUndo('Instructions added under the plan. Read them as the '
              'patient will.');
        case InstructionsAction.copied:
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Copied. Generated text — check it against the '
                  'plan before sharing.'),
            ),
          );
        case InstructionsAction.dismissed:
          break;
      }
    } on DraftRefused catch (refusal) {
      messenger.showSnackBar(SnackBar(content: Text(refusal.reason)));
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  /// True while this section still holds exactly what the model put there.
  bool _isGenerated(String key) =>
      _aiText[key] != null && _fields[key]!.text == _aiText[key];

  /// The model-drafting action under a section, or null where none applies.
  Widget? _aiActionFor(String key, bool isLocked) {
    if (isLocked || key != 'plan') return null;
    if (!context.watch<AppBootstrap>().assistModelActive) return null;

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _drafting || _plan.text.trim().isEmpty
            ? null
            : _explainForPatient,
        icon: _drafting
            ? const AiSparkleIcon(size: 16)
            : const Icon(Icons.auto_awesome_outlined, size: 16),
        label: Text(_drafting ? 'Working…' : 'Explain for the patient'),
      ),
    );
  }

  Widget _soapField(String key, bool isLocked) {
    final label = _fieldLabels[key]!;
    return Padding(
      padding: EdgeInsets.only(bottom: context.metrics.spaceMd),
      child: _SoapField(
        letter: label[0],
        title: label,
        hint: _hints[key]!,
        controller: _fields[key]!,
        enabled: !isLocked,
        attachments: _forSection(label),
        paths: _attachmentPaths,
        onDictate: () => _dictate(key),
        transcribingId: _transcribingId,
        onTranscribe: context.watch<AppBootstrap>().canTranscribe && !isLocked
            ? (attachment) => _transcribeExisting(attachment, label)
            : null,
        onCaptured: ({
          required file,
          required kind,
          mimeType,
          durationMs,
        }) =>
            _attach(
          file: file,
          kind: kind,
          section: label,
          mimeType: mimeType,
          durationMs: durationMs,
        ),
        onDeleteAttachment: _removeAttachment,
        aiAction: _aiActionFor(key, isLocked),
        isGenerated: _isGenerated(key),
      ),
    );
  }

  static const Map<String, String> _hints = <String, String>{
    'subjective': 'History, symptoms, what the patient reports',
    'objective': 'Examination findings, observations, results',
    'assessment': 'Impression, differential, reasoning',
    'plan': 'Treatment, investigations, safety-netting, follow-up',
  };
}

class _SoapField extends StatelessWidget {
  const _SoapField({
    required this.letter,
    required this.title,
    required this.hint,
    required this.controller,
    required this.enabled,
    required this.attachments,
    required this.paths,
    required this.onCaptured,
    required this.onDeleteAttachment,
    required this.onDictate,
    required this.onTranscribe,
    required this.transcribingId,
    this.aiAction,
    this.isGenerated = false,
  });

  final String letter;
  final String title;
  final String hint;
  final TextEditingController controller;
  final bool enabled;
  final List<Attachment> attachments;
  final Map<String, String> paths;
  final Future<void> Function({
    required File file,
    required AttachmentKind kind,
    String? mimeType,
    int? durationMs,
  }) onCaptured;
  final void Function(Attachment) onDeleteAttachment;
  final VoidCallback onDictate;
  final void Function(Attachment)? onTranscribe;
  final String? transcribingId;

  /// A model-drafting action for this section — sort, reword — or null when
  /// no model is installed or the section has none. Rendered under the text
  /// so the field itself stays what it is everywhere else in the app.
  final Widget? aiAction;

  /// True while this section holds text the model wrote and nobody has edited.
  /// The badge comes off on the first keystroke — the rule the design system
  /// states for generated content everywhere.
  final bool isGenerated;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return SectionCard(
      title: title,
      leading: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.primaryContainer,
          borderRadius: BorderRadius.circular(m.radiusSm - 2),
        ),
        child: Text(
          letter,
          style: context.texts.labelLarge
              ?.copyWith(color: palette.onPrimaryContainer),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isGenerated) ...<Widget>[
            const AiBadge(dense: true),
            SizedBox(width: m.spaceXs),
          ],
          FieldAttachBar(
            enabled: enabled,
            onCaptured: onCaptured,
            onDictate: onDictate,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: controller,
            enabled: enabled,
            maxLines: null,
            minLines: 3,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: context.texts.bodyMedium,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          ?aiAction,
          // Evidence sits under the text it belongs to, playable and viewable
          // in place — never filed away on a separate screen.
          AttachmentStrip(
            attachments: attachments,
            paths: paths,
            onDelete: enabled ? onDeleteAttachment : null,
            onTranscribe: onTranscribe,
            transcribingId: transcribingId,
          ),
        ],
      ),
    );
  }
}

class _SignatureBar extends StatelessWidget {
  const _SignatureBar({required this.note});

  final ClinicalNote note;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;
    final intact = note.verifyIntegrity();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: m.spaceLg,
        vertical: m.spaceSm,
      ),
      color: intact ? palette.surfaceSunken : palette.criticalSubtle,
      child: Row(
        children: <Widget>[
          Icon(
            intact ? Icons.verified_outlined : Icons.gpp_bad_outlined,
            size: 16,
            color: intact ? palette.signedLock : palette.critical,
          ),
          SizedBox(width: m.spaceSm),
          Expanded(
            child: Text(
              intact
                  ? 'Signed by ${note.signedBy ?? 'unknown'} · '
                      '${Fmt.dateTime(note.signedAt)}'
                  : 'Integrity check failed — stored content does not match '
                      'the signature',
              style: context.texts.labelSmall?.copyWith(
                color: intact ? palette.onSurfaceMuted : palette.critical,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmendmentList extends StatelessWidget {
  const _AmendmentList({required this.amendments});

  final List<NoteAmendment> amendments;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return SectionCard(
      title: 'Amendments',
      subtitle: 'Appended after signing — the original text is unchanged',
      leading: const Icon(Icons.playlist_add_check_outlined, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: amendments.map((amendment) {
          return Padding(
            padding: EdgeInsets.only(bottom: m.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${Fmt.dateTime(amendment.createdAt)} · '
                  '${amendment.author ?? 'unknown'}',
                  style: context.texts.labelSmall,
                ),
                Text(
                  'Reason: ${amendment.reason}',
                  style: context.texts.labelMedium,
                ),
                SizedBox(height: m.spaceXs),
                Text(amendment.body, style: context.texts.bodyMedium),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}


/// The three bulk actions, spelled out.
///
/// These were icon-only buttons in the app bar: a page icon for "insert
/// template" and a copy icon for "copy forward". Neither is guessable — the
/// page icon is used for documents, articles, notes and lists across the
/// platform, and a copy icon in a text editor means copy the text. An action
/// that rewrites four fields cannot be behind a glyph the user has to tap to
/// learn. They are labelled, and they sit above the fields they change.
class _NoteToolbar extends StatelessWidget {
  const _NoteToolbar({
    required this.onTemplate,
    required this.onCopyForward,
    required this.onDictate,
  });

  final VoidCallback onTemplate;
  final VoidCallback onCopyForward;
  final VoidCallback onDictate;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: m.spaceLg,
        vertical: m.spaceSm,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        border: Border(
          bottom: BorderSide(color: palette.outline, width: m.hairline),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            _ToolbarButton(
              icon: Icons.mic_none_outlined,
              label: 'Dictate',
              onPressed: onDictate,
              emphasised: true,
            ),
            SizedBox(width: m.spaceSm),
            _ToolbarButton(
              icon: Icons.dashboard_customize_outlined,
              label: 'Template',
              onPressed: onTemplate,
            ),
            SizedBox(width: m.spaceSm),
            _ToolbarButton(
              icon: Icons.history_edu_outlined,
              label: 'Copy forward',
              onPressed: onCopyForward,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      foregroundColor:
          emphasised ? context.palette.primary : context.palette.onSurface,
    );
    return emphasised
        ? FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
          )
        : TextButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }
}

/// Structured entries the written text implies, offered rather than applied.
///
/// This exists because of a specific, ordinary failure: a clinician writes
/// "started on amlodipine 5mg" in the plan and the medication list still says
/// nothing. Six months later the medication list is not trustworthy enough to
/// prescribe against. Every row here is one tap to file and one tap to
/// dismiss, and dismissal is remembered so the same suggestion does not
/// reappear on the next keystroke.
class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.suggestions,
    required this.onAccept,
    required this.onDismiss,
  });

  final List<ExtractedTerm> suggestions;
  final Future<void> Function(ExtractedTerm) onAccept;
  final void Function(ExtractedTerm) onDismiss;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return SectionCard(
      title: 'From your note',
      subtitle: 'Nothing is filed until you tap it',
      leading: const AiSparkleIcon(size: 20),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AiBadge(label: 'Suggested', dense: true),
          InfoDot(
            explanation: NoteIntelligence.explain(suggestions.length),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final term in suggestions)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceSm),
              child: Row(
                children: <Widget>[
                  Icon(
                    switch (term.kind) {
                      ExtractedTermKind.medication =>
                        Icons.medication_outlined,
                      ExtractedTermKind.problem => Icons.checklist_outlined,
                      ExtractedTermKind.allergy =>
                        Icons.warning_amber_outlined,
                      ExtractedTermKind.redFlag => Icons.priority_high,
                      ExtractedTermKind.followUp =>
                        Icons.event_available_outlined,
                    },
                    size: 17,
                    color: term.kind == ExtractedTermKind.redFlag
                        ? palette.critical
                        : palette.onSurfaceMuted,
                  ),
                  SizedBox(width: m.spaceSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(term.text, style: context.texts.bodyMedium),
                        Text(
                          '${term.kind.label} · from "${term.matchedPhrase}"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  // A red flag is a prompt to think, not a record to file, so
                  // it gets no "add" action — only acknowledgement.
                  if (term.kind != ExtractedTermKind.redFlag)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Add to chart',
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: () => onAccept(term),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => onDismiss(term),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.dirty, required this.savedAt});

  final bool dirty;
  final DateTime? savedAt;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          dirty ? Icons.sync : Icons.cloud_done_outlined,
          size: 14,
          color: palette.onSurfaceMuted,
        ),
        SizedBox(width: m.spaceXs),
        Text(
          dirty
              ? 'Saving…'
              : savedAt == null
                  ? 'Autosaves as you type'
                  : 'Saved ${Fmt.time(savedAt)}',
          style: context.texts.labelSmall,
        ),
      ],
    );
  }
}


/// "That was inserted — you can take it back", with a timer this app owns.
class _UndoBanner extends StatelessWidget {
  const _UndoBanner({
    required this.message,
    required this.onUndo,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      margin: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceXs),
      padding: EdgeInsets.fromLTRB(m.spaceMd, m.spaceSm, m.spaceXs, m.spaceSm),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
        border: Border.all(color: palette.outline, width: m.hairline),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.history, size: 16, color: palette.onSurfaceMuted),
          SizedBox(width: m.spaceSm),
          Expanded(
            child: Text(message, style: context.texts.bodySmall),
          ),
          TextButton(
            onPressed: onUndo,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Undo'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// The rough-draft box that sits above the four sections.
///
/// It exists because the SOAP structure describes where a note *ends up*, not
/// how it is produced: a clinician talks through a consultation in the order
/// it happened, and asking them to pre-sort into four boxes as they speak is
/// asking them to do the work the structure was supposed to save.
///
/// So this is a plain scratch box with a microphone, and — when a model is
/// installed — one button that distributes what is in it. Without a model it
/// is still useful on its own: somewhere to put words while a patient is
/// still talking. It is deliberately not part of the signed record, and the
/// editor refuses to sign quietly while anything is still sitting in it.
class _WorkingNotesCard extends StatelessWidget {
  const _WorkingNotesCard({
    required this.controller,
    required this.hasModel,
    required this.isDrafting,
    required this.onSort,
    required this.onDictate,
  });

  final TextEditingController controller;
  final bool hasModel;
  final bool isDrafting;
  final VoidCallback onSort;
  final VoidCallback onDictate;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasText = controller.text.trim().isNotEmpty;

        return SectionCard(
          title: 'Working notes',
          subtitle: 'Talk or type it all here — sort it after',
          leading: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: BorderRadius.circular(m.radiusSm - 2),
            ),
            child: Icon(
              Icons.edit_note,
              size: 18,
              color: palette.onSurfaceMuted,
            ),
          ),
          trailing: IconButton(
            tooltip: 'Dictate into the working notes',
            icon: const Icon(Icons.mic_none_outlined),
            onPressed: onDictate,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: controller,
                maxLines: null,
                minLines: 3,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: context.texts.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Whatever the consultation produced, in any '
                      'order. Nothing here is part of the signed note.',
                  hintStyle: context.texts.bodySmall
                      ?.copyWith(color: palette.onSurfaceMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (hasText) ...<Widget>[
                SizedBox(height: m.spaceSm),
                if (hasModel)
                  AiGlowBorder(
                    active: isDrafting,
                    borderRadius: BorderRadius.circular(m.radiusSm),
                    child: FilledButton.tonalIcon(
                      onPressed: isDrafting ? null : onSort,
                      icon: isDrafting
                          ? const AiSparkleIcon(size: 18)
                          : const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: Text(
                        isDrafting
                            ? 'Sorting…'
                            : 'Sort into S · O · A · P',
                      ),
                    ),
                  )
                else
                  Text(
                    'Install an assistant model in Settings › On-device AI to '
                    'have this sorted into the four sections for you.',
                    style: context.texts.labelSmall
                        ?.copyWith(color: palette.onSurfaceMuted),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
