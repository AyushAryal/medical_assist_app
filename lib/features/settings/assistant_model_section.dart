import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../../data/services/assist/assist_model_catalog.dart';
import '../../data/services/model_download.dart';
import 'model_row.dart';

/// Installing, choosing and removing the assistant's language model.
///
/// The copy above the list carries the two facts that decide whether to
/// install one at all: what it adds (questions the built-in matching cannot
/// phrase-match get translated instead of refused), and what it never does
/// (see the register, leave the device, or answer anything itself — it
/// rewrites wording, and the same tested matcher runs the rewrite). The
/// licence is stated per model because installing one is accepting it.
class AssistantModelSection extends StatefulWidget {
  const AssistantModelSection({super.key});

  @override
  State<AssistantModelSection> createState() => _AssistantModelSectionState();
}

class _AssistantModelSectionState extends State<AssistantModelSection> {
  final Map<String, int> _installedBytes = <String, int>{};
  final Set<String> _complete = <String>{};

  String? _sideloadPath;
  AssistModel? _installing;
  ModelInstallProgress? _progress;
  CancellationToken? _cancellation;
  String? _error;

  /// The device class the recommendation is tuned to. Defaults to the common
  /// mid-range clinic tablet; the operator narrows it to their fleet. Held in
  /// view state only — it steers what is highlighted, it is not a setting that
  /// changes what runs.
  DeviceClass _deviceClass = DeviceClass.standard;

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
    final manager = context.read<AppBootstrap>().assistModels;
    final complete = <String>{};
    final bytes = <String, int>{};
    for (final model in AssistModelCatalog.models) {
      if (await manager.installed(model) != null) complete.add(model.id);
      bytes[model.id] = await manager.bytesOnDisk(model);
    }
    final sideload =
        await manager.sideloadPathFor(AssistModelCatalog.models.first);
    if (!mounted) return;
    setState(() {
      _complete
        ..clear()
        ..addAll(complete);
      _installedBytes
        ..clear()
        ..addAll(bytes);
      _sideloadPath = sideload;
    });
  }

  Future<void> _install(AssistModel model) async {
    final bootstrap = context.read<AppBootstrap>();
    final cancellation = CancellationToken();
    setState(() {
      _installing = model;
      _cancellation = cancellation;
      _progress = null;
      _error = null;
    });

    try {
      await bootstrap.assistModels.download(
        model,
        cancellation: cancellation,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      await bootstrap.refreshAssistEngine();
    } on ModelInstallException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _installing = null;
          _cancellation = null;
          _progress = null;
        });
        await _refresh();
      }
    }
  }

  /// How [model] suits the selected device class: the single recommended pick,
  /// something that merely fits, or something heavier than the class allows.
  ModelSuitability _suitabilityOf(AssistModel model) {
    if (model.id == AssistModelCatalog.recommendedFor(_deviceClass).id) {
      return ModelSuitability.recommended;
    }
    return _deviceClass.meets(model.minDeviceClass)
        ? ModelSuitability.fits
        : ModelSuitability.heavy;
  }

  Future<void> _use(AssistModel model) async {
    await context.read<AppBootstrap>().setAssistModel(model);
    await _refresh();
  }

  Future<void> _remove(AssistModel model) async {
    final bootstrap = context.read<AppBootstrap>();
    await bootstrap.assistModels.remove(model);
    await bootstrap.refreshAssistEngine();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final bootstrap = context.watch<AppBootstrap>();
    final active = bootstrap.activeAssistModel;

    return SectionCard(
      title: 'Assistant language model',
      subtitle: active == null
          ? 'Optional — the assistant already answers most questions without '
              'one'
          : 'Using ${active.name}',
      leading: const AiSparkleIcon(size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Three jobs, all rewording. Assistant questions the built-in '
            'matching cannot phrase-match are translated into supported '
            'ones, and the same tested matcher runs the translation. In the '
            'note editor it can sort a dictation into S·O·A·P — refused '
            'outright if it changes a single word — and reword a plan as '
            'patient instructions, always previewed and badged. The model '
            'never sees the register, never leaves this device, and cannot '
            'write anything into a record by itself.',
            style: context.texts.bodySmall,
          ),
          SizedBox(height: m.spaceMd),

          if (_error case final error?) ...<Widget>[
            Text(
              error,
              style: context.texts.bodySmall
                  ?.copyWith(color: context.palette.critical),
            ),
            SizedBox(height: m.spaceSm),
          ],

          _DeviceClassPicker(
            selected: _deviceClass,
            onChanged: (value) => setState(() => _deviceClass = value),
          ),
          SizedBox(height: m.spaceSm),
          Text(
            'A bigger model follows the wording more reliably but needs more '
            'memory to run beside the record and the transcriber. Pick the '
            'device you are installing on and the best fit is marked '
            '“Recommended”; a model too heavy for it is marked, not hidden — '
            'you can still install it.',
            style: context.texts.labelSmall
                ?.copyWith(color: context.palette.onSurfaceMuted),
          ),
          SizedBox(height: m.spaceMd),

          for (final model in AssistModelCatalog.models) ...<Widget>[
            ModelRow(
              name: '${model.name} · ${model.parameters}',
              description: '${model.description} Licence: ${model.licence}.',
              sizeLabel: model.sizeLabel,
              memoryLabel: model.runtimeMemoryLabel,
              suitability: _suitabilityOf(model),
              activeLine: 'Translating unmatched questions with this model.',
              isComplete: _complete.contains(model.id),
              isActive: active?.id == model.id,
              isSideloaded: false,
              onUse: _complete.contains(model.id) && active?.id != model.id
                  ? () => _use(model)
                  : null,
              bytesOnDisk: _installedBytes[model.id] ?? 0,
              isInstalling: _installing?.id == model.id,
              progress: _installing?.id == model.id ? _progress : null,
              onInstall: _installing == null ? () => _install(model) : null,
              onCancel: () => _cancellation?.cancel(),
              onRemove: (_installedBytes[model.id] ?? 0) > 0 &&
                      _installing == null
                  ? () => _remove(model)
                  : null,
            ),
            if (model != AssistModelCatalog.models.last)
              SectionCard.divider(context),
          ],

          if (_sideloadPath case final path?) ...<Widget>[
            SizedBox(height: m.spaceMd),
            Text(
              'Airgapped install: push a listed model file with adb to\n$path',
              style: context.texts.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// The device-class chooser above the model list.
///
/// A self-select rather than an autodetect: total RAM is not readable without a
/// platform plugin and free RAM lies moment to moment, so the operator — who
/// knows the tablet in their hand — sets the band, and the app states what each
/// model needs against it. Three bands are all the recommendation turns on.
class _DeviceClassPicker extends StatelessWidget {
  const _DeviceClassPicker({required this.selected, required this.onChanged});

  final DeviceClass selected;
  final ValueChanged<DeviceClass> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'This device',
          style: context.texts.labelMedium,
        ),
        SizedBox(height: m.spaceXs),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<DeviceClass>(
            segments: <ButtonSegment<DeviceClass>>[
              for (final deviceClass in DeviceClass.values)
                ButtonSegment<DeviceClass>(
                  value: deviceClass,
                  label: Text(
                    '${deviceClass.label}\n${deviceClass.memoryHint}',
                    textAlign: TextAlign.center,
                    style: context.texts.labelSmall,
                  ),
                ),
            ],
            selected: <DeviceClass>{selected},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
      ],
    );
  }
}
