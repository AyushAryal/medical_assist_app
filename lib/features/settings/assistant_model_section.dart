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
            'Adds a translator for questions the built-in matching cannot '
            'phrase-match: wording it does not recognise is rewritten into '
            'one of the supported questions, and the same tested matcher '
            'runs the rewrite. The model never sees the register, never '
            'leaves this device, and cannot answer anything by itself — a '
            'rewrite the matcher refuses goes nowhere.',
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

          for (final model in AssistModelCatalog.models) ...<Widget>[
            ModelRow(
              name: '${model.name} · ${model.parameters}',
              description: '${model.description} Licence: ${model.licence}.',
              sizeLabel: model.sizeLabel,
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
