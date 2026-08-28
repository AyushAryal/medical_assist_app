import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../../data/services/dictation_recorder.dart';
import '../../data/services/transcription/speech_model.dart';
import 'assistant_model_section.dart';
import 'model_row.dart';

/// Dictation and speech recognition settings.
///
/// The honest disclosure at the top of this screen is the point of it. Every
/// other claim the app makes about privacy rests on there being no network
/// code, and installing a speech model is the one exception — so it is stated
/// here, in the place where a user chooses to take it, rather than buried in a
/// document. The side-load path exists so a deployment that cannot accept even
/// that exception is still able to use the feature.
class DictationSettingsScreen extends StatefulWidget {
  const DictationSettingsScreen({super.key});

  @override
  State<DictationSettingsScreen> createState() =>
      _DictationSettingsScreenState();
}

class _DictationSettingsScreenState extends State<DictationSettingsScreen> {
  final Map<String, int> _installedBytes = <String, int>{};
  final Set<String> _complete = <String>{};
  final Set<String> _sideloaded = <String>{};

  /// Where a model can be pushed from a laptop with no root and no permission.
  String? _sideloadPath;

  SpeechModel? _installing;
  ModelInstallProgress? _progress;
  CancellationToken? _cancellation;
  String? _error;

  DictationQuality _quality = DictationQuality.full;
  bool _keepOriginal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final bootstrap = context.read<AppBootstrap>();
    final stored = await bootstrap.meta.read(_qualityKey);

    for (final model in SpeechModel.all) {
      _installedBytes[model.id] =
          await bootstrap.speechModels.bytesOnDisk(model);
      if (await bootstrap.speechModels.installed(model) != null) {
        _complete.add(model.id);
        if (await bootstrap.speechModels.isSideloaded(model)) {
          _sideloaded.add(model.id);
        } else {
          _sideloaded.remove(model.id);
        }
      } else {
        _complete.remove(model.id);
        _sideloaded.remove(model.id);
      }
    }

    final pushTarget = await bootstrap.speechModels.sideloadPathFor(
      SpeechModel.all.first,
    );

    if (!mounted) return;
    setState(() {
      // The parent, since every model gets its own folder beneath it.
      _sideloadPath = pushTarget == null
          ? null
          : p.dirname(pushTarget);
      _quality = stored == DictationQuality.compact.name
          ? DictationQuality.compact
          : DictationQuality.full;
    });

    final keep = await bootstrap.meta.read(AppBootstrap.keepOriginalAudioKey);
    if (!mounted) return;
    setState(() => _keepOriginal = keep == 'true');
  }

  /// Shared with [AppBootstrap], which reads it at unlock to configure the
  /// recorder. Two spellings of one key is exactly the bug that makes a
  /// setting appear not to persist.
  static const String _qualityKey = AppBootstrap.dictationQualityKey;

  Future<void> _setQuality(DictationQuality quality) async {
    final bootstrap = context.read<AppBootstrap>();
    setState(() => _quality = quality);
    bootstrap.dictation.quality = quality;
    await bootstrap.meta.write(_qualityKey, quality.name);
  }

  Future<void> _setKeepOriginal(bool value) async {
    final bootstrap = context.read<AppBootstrap>();
    setState(() => _keepOriginal = value);
    bootstrap.dictation.keepOriginal = value;
    await bootstrap.meta.write(
      AppBootstrap.keepOriginalAudioKey,
      value.toString(),
    );
  }

  Future<void> _install(SpeechModel model) async {
    final confirmed = await _confirmDownload(model);
    if (confirmed != true || !mounted) return;

    final bootstrap = context.read<AppBootstrap>();
    final cancellation = CancellationToken();

    setState(() {
      _installing = model;
      _cancellation = cancellation;
      _error = null;
      _progress = ModelInstallProgress(
        receivedBytes: 0,
        totalBytes: model.totalBytes,
        currentFile: model.tokensFile,
      );
    });

    try {
      await bootstrap.speechModels.download(
        model,
        cancellation: cancellation,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      await bootstrap.refreshTranscriptionEngine();
    } on ModelInstallException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Install failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _installing = null;
          _progress = null;
          _cancellation = null;
        });
        await _refresh();
      }
    }
  }

  Future<bool> _confirmDownload(SpeechModel model) {
    return confirmDialog(
      context,
      title: 'Download the speech model?',
      message: 'This is the only time this app makes a network request.\n\n'
          'It downloads ${model.sizeLabel} of model files from a public '
          'repository. No patient information, no identifier and no usage '
          'data is sent — the request contains nothing but the file name.\n\n'
          'Once installed, all transcription happens on this device and '
          'nothing further is ever transmitted.\n\n'
          'If this device must never reach a network, cancel and use "Load '
          'from a file" instead.',
      confirmLabel: 'Download ${model.sizeLabel}',
    );
  }

  /// Imports model files the operator supplied themselves.
  ///
  /// Multi-select, because a model is three files and picking them one at a
  /// time means three trips through the system document picker to accomplish
  /// one task.
  Future<void> _sideLoad() async {
    final messenger = ScaffoldMessenger.of(context);
    final bootstrap = context.read<AppBootstrap>();

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['onnx', 'txt'],
    );
    if (picked.isEmpty) return;

    final rejected = <String>[];
    var accepted = 0;
    SpeechModel? target;

    for (final file in picked) {
      final path = file.path;
      if (path == null) continue;
      final result =
          await bootstrap.speechModels.importFromFile(File(path));
      if (result.accepted) {
        accepted++;
        target = result.model;
      } else if (result.problem != null) {
        rejected.add(result.problem!);
      }
    }

    if (!mounted) return;

    await bootstrap.refreshTranscriptionEngine();
    await _refresh();
    if (!mounted) return;

    // Report the rejections rather than swallowing them: a silent partial
    // import looks like the feature is broken.
    setState(() => _error = rejected.isEmpty ? null : rejected.join('\n\n'));

    if (accepted == 0) return;
    final complete =
        target != null && await bootstrap.speechModels.installed(target) != null;
    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          complete
              ? '${target.name} is now complete and ready to use.'
              : 'Added $accepted file${accepted == 1 ? '' : 's'}. '
                  '${target == null ? 'More' : '${target.name} needs more'} '
                  'files before it can run.',
        ),
      ),
    );
  }

  /// Switches which installed model transcribes.
  ///
  /// Needed because both models can be installed at once and only one can be
  /// live: without this the first one in the list wins permanently, which is
  /// exactly the wrong behaviour for a clinic that installed the multilingual
  /// model on purpose.
  Future<void> _use(SpeechModel model) async {
    final messenger = ScaffoldMessenger.of(context);
    await context.read<AppBootstrap>().setSpeechModel(model);
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Now transcribing with ${model.name}.')),
    );
  }

  Future<void> _remove(SpeechModel model) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Remove ${model.name}?',
      message:
          'Frees ${model.sizeLabel}. Recordings already transcribed keep their '
          'text — transcripts are stored in the note, not regenerated. New '
          'dictation will be attached as audio only until a model is '
          'installed again.',
      confirmLabel: 'Remove',
    );
    if (confirmed != true || !mounted) return;

    final bootstrap = context.read<AppBootstrap>();
    await bootstrap.speechModels.remove(model);
    await bootstrap.refreshTranscriptionEngine();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final bootstrap = context.watch<AppBootstrap>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('On-device AI')),
      body: ContentWidth(
        child: ListView(
          padding: pagePadding(context, floatingBar: false),
          children: <Widget>[
            _PrivacyNote(active: bootstrap.canTranscribe),
            SizedBox(height: m.spaceMd),

            if (_error case final error?) ...<Widget>[
              _ErrorPanel(
                message: error,
                onDismiss: () => setState(() => _error = null),
              ),
              SizedBox(height: m.spaceMd),
            ],

            SectionCard(
              title: 'Speech recognition',
              subtitle: bootstrap.canTranscribe
                  ? 'Using ${bootstrap.transcription.name}'
                  : 'Not set up — dictation is attached as audio only',
              leading: const Icon(Icons.record_voice_over_outlined, size: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final model in SpeechModel.all) ...<Widget>[
                    ModelRow(
                      name: model.name,
                      description: model.description,
                      sizeLabel: model.sizeLabel,
                      activeLine: 'Transcribing with this model.',
                      isComplete: _complete.contains(model.id),
                      isActive: bootstrap.activeSpeechModel?.id == model.id,
                      isSideloaded: _sideloaded.contains(model.id),
                      onUse: _complete.contains(model.id) &&
                              bootstrap.activeSpeechModel?.id != model.id
                          ? () => _use(model)
                          : null,
                      bytesOnDisk: _installedBytes[model.id] ?? 0,
                      isInstalling: _installing?.id == model.id,
                      progress:
                          _installing?.id == model.id ? _progress : null,
                      onInstall: _installing == null
                          ? () => _install(model)
                          : null,
                      onCancel: () => _cancellation?.cancel(),
                      onRemove: (_installedBytes[model.id] ?? 0) > 0 &&
                              _installing == null
                          ? () => _remove(model)
                          : null,
                    ),
                    if (model != SpeechModel.all.last)
                      SectionCard.divider(context),
                  ],
                  SizedBox(height: m.spaceSm),
                  OutlinedButton.icon(
                    onPressed: _installing == null ? _sideLoad : null,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Load from a file instead'),
                  ),
                  SizedBox(height: m.spaceXs),
                  Text(
                    'Select all three files at once. Each is checked against '
                    'its expected size before it is accepted, so a truncated '
                    'download cannot be installed.',
                    style: context.texts.labelSmall,
                  ),
                  if (_sideloadPath case final path?) ...<Widget>[
                    SizedBox(height: m.spaceMd),
                    _SideloadPath(path: path),
                  ],
                ],
              ),
            ),
            SizedBox(height: m.spaceMd),

            // The assistant's language models — separate section, same rules.
            const AssistantModelSection(),
            SizedBox(height: m.spaceMd),

            SectionCard(
              title: 'Recording quality',
              subtitle: 'Silence is always removed, whichever you choose',
              leading: const Icon(Icons.graphic_eq, size: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  RadioGroup<DictationQuality>(
                    groupValue: _quality,
                    onChanged: (value) {
                      if (value != null) _setQuality(value);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final quality in DictationQuality.values)
                          RadioListTile<DictationQuality>(
                            value: quality,
                            contentPadding: EdgeInsets.zero,
                            title: Text(quality.label),
                            subtitle: Text(quality.detail),
                          ),
                      ],
                    ),
                  ),
                  SectionCard.divider(context),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _keepOriginal,
                    onChanged: _setKeepOriginal,
                    title: const Text('Keep the original recording too'),
                    subtitle: const Text(
                      'Attaches the untrimmed audio alongside the trimmed '
                      'one. Roughly doubles what each dictation costs to '
                      'store.',
                    ),
                  ),
                  Text(
                    _keepOriginal
                        ? 'Both files are attached to the note. The trimmed '
                            'one is what plays back; the original is exactly '
                            'what the microphone heard.'
                        : 'Trimming is biased toward keeping audio and the '
                            'transcript is reviewed before it can reach a '
                            'note, so the original is not usually needed. Turn '
                            'this on where a dictation may be disputed, or '
                            'until you trust the trimming on this hardware.',
                    style: context.texts.labelSmall,
                  ),
                  SectionCard.divider(context),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Recordings are uncompressed so they can be both '
                          'transcribed and played back without a codec. '
                          'Trimming the pauses is what keeps that affordable.',
                          style: context.texts.labelSmall,
                        ),
                      ),
                      InfoDot(
                        explanation: _storageExplanation(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  MetricExplanation _storageExplanation() {
    final perMinute = _quality == DictationQuality.compact ? 960 : 1875;
    return MetricExplanation(
      title: 'What a dictation costs to store',
      summary: 'Recordings are 16-bit linear PCM in a WAV container — the one '
          'format that both the speech recogniser and every platform audio '
          'player accept without a codec.',
      method: <String>[
        'Audio is captured at 16 kHz mono, which is the rate the speech model '
            'expects.',
        'Stretches where nobody was speaking are removed before anything is '
            'written. On ordinary dictation that is typically 30–50% of the '
            'recording.',
        if (_quality == DictationQuality.compact)
          'The stored copy is then halved to 8 kHz. Transcription still runs '
              'on the full-rate audio, so accuracy is unaffected.',
        'What remains costs about ${(perMinute / 1024).toStringAsFixed(1)} MB '
            'per minute of *speech* — not per minute of recording.',
      ],
      derivation: <ExplainRow>[
        ExplainRow(
          label: 'Sample rate stored',
          value: '${_quality.storedSampleRate ~/ 1000} kHz mono',
        ),
        ExplainRow(
          label: 'Per minute of speech',
          value: '${(perMinute / 1024).toStringAsFixed(1)} MB',
        ),
        ExplainRow(
          label: 'A 90-second dictation with 40% pauses',
          value: '${(perMinute * 0.9 / 1024).toStringAsFixed(1)} MB',
        ),
      ],
      confidence: ExplainConfidence.measured,
      caveat: 'A compressed format would be several times smaller, but no '
          'compressed audio can be decoded in this app without adding a codec '
          'the device may not have. The real answer to storage is the '
          'transcript: once a dictation is text in the note, the audio is a '
          'fallback that is rarely opened, and it can be removed from the '
          'note like any other attachment.',
    );
  }
}

/// The disclosure, stated where the choice is made.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.all(m.spaceLg),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusMd),
        border: Border.all(color: palette.outline, width: m.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.lock_outline, size: 18, color: palette.normal),
              SizedBox(width: m.spaceSm),
              Expanded(
                child: Text(
                  'Transcription happens on this device',
                  style: context.texts.titleSmall,
                ),
              ),
            ],
          ),
          SizedBox(height: m.spaceSm),
          Text(
            active
                ? 'A speech model is installed. Recordings are transcribed '
                    'locally and no audio, transcript or patient detail leaves '
                    'this device.'
                : 'No speech model is installed yet. Dictation still works — '
                    'the recording is attached to the note — but it will not '
                    'be turned into text.',
            style: context.texts.bodySmall,
          ),
          SizedBox(height: m.spaceSm),
          Text(
            'Installing a model is the only network request this app can make, '
            'and it carries nothing but a public file name.',
            style: context.texts.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.all(m.spaceMd),
      decoration: BoxDecoration(
        color: palette.criticalSubtle,
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: palette.critical),
          SizedBox(width: m.spaceSm),
          Expanded(child: Text(message, style: context.texts.bodySmall)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}


/// The exact path to push a model to, with the reason it is worth knowing.
class _SideloadPath extends StatelessWidget {
  const _SideloadPath({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.all(m.spaceMd),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
        border: Border.all(color: palette.outline, width: m.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.usb, size: 15, color: palette.onSurfaceMuted),
              SizedBox(width: m.spaceSm),
              Expanded(
                child: Text(
                  'Or provision from a computer',
                  style: context.texts.labelMedium,
                ),
              ),
            ],
          ),
          SizedBox(height: m.spaceXs),
          Text(
            'Models placed in this folder are picked up automatically. It needs '
            'no root and no permission on either side, so a fleet of devices '
            'can be provisioned with one command each.',
            style: context.texts.labelSmall,
          ),
          SizedBox(height: m.spaceSm),
          SelectableText(
            '$path/<model-id>/',
            style: context.texts.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: palette.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
