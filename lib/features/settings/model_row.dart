import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../data/services/model_download.dart';

/// How a model suits the device class the operator has selected.
///
/// Only the assistant's language models carry this; the speech models leave it
/// null and the row shows nothing. It never blocks an install — a clinic that
/// wants a heavy model on a light device may have reasons the app cannot see —
/// it only says, plainly, what to expect.
enum ModelSuitability {
  /// The best model this device class runs comfortably. The one to pick.
  recommended,

  /// Runs on this device class, but not the recommended pick.
  fits,

  /// Needs more memory than this device class has to spare. Installable, but
  /// likely to be slow or to be killed under load.
  heavy,
}

/// One installable model: what it is, what state it is in, what can be done.
///
/// Shared between the speech models and the assistant's language models so
/// the two installs read identically — same progress, same resume wording,
/// same refusal of a truncated file. Two model UIs that behave differently
/// would make one of them look broken.
class ModelRow extends StatelessWidget {
  const ModelRow({
    super.key,
    required this.name,
    required this.description,
    required this.sizeLabel,
    required this.activeLine,
    required this.isComplete,
    required this.isActive,
    required this.isSideloaded,
    required this.onUse,
    required this.bytesOnDisk,
    required this.isInstalling,
    required this.progress,
    required this.onInstall,
    required this.onCancel,
    required this.onRemove,
    this.memoryLabel,
    this.suitability,
  });

  /// What the model is, as plain strings — this row serves both the speech
  /// models and the assistant's language models, and knowing either type
  /// would tie it to one family.
  final String name;
  final String description;
  final String sizeLabel;

  /// The line shown when this model is the one in use.
  final String activeLine;

  final bool isComplete;

  /// The model transcription is currently using. Only one can be.
  final bool isActive;

  /// Installed from external storage rather than downloaded. Behaves
  /// identically; worth stating so an operator knows which copy is live.
  final bool isSideloaded;

  /// Switches to this model. Null when it is already active or not installed.
  final VoidCallback? onUse;
  final int bytesOnDisk;
  final bool isInstalling;
  final ModelInstallProgress? progress;
  final VoidCallback? onInstall;
  final VoidCallback onCancel;
  final VoidCallback? onRemove;

  /// Roughly the working memory the model needs to run, when known. Shown so a
  /// small download is not mistaken for a small runtime cost.
  final String? memoryLabel;

  /// How the model suits the selected device class, or null to say nothing.
  final ModelSuitability? suitability;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final partial = !isComplete && bytesOnDisk > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(name, style: context.texts.titleSmall),
                      ),
                      if (suitability == ModelSuitability.recommended) ...<Widget>[
                        SizedBox(width: m.spaceXs),
                        StatusPill(
                          label: 'Recommended',
                          tone: PillTone.normal,
                          icon: Icons.verified_outlined,
                          dense: true,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: m.spaceXs / 2),
                  Text(description, style: context.texts.bodySmall),
                  if (memoryLabel case final memory?) ...<Widget>[
                    SizedBox(height: m.spaceXs / 2),
                    Text(
                      'Needs about $memory to run',
                      style: context.texts.labelSmall
                          ?.copyWith(color: palette.onSurfaceMuted),
                    ),
                  ],
                  if (suitability == ModelSuitability.heavy) ...<Widget>[
                    SizedBox(height: m.spaceXs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.warning_amber_rounded,
                            size: 13, color: palette.caution),
                        SizedBox(width: m.spaceXs),
                        Expanded(
                          child: Text(
                            'Heavier than this device class — it may run slowly '
                            'or be closed under load. Installable anyway.',
                            style: context.texts.labelSmall
                                ?.copyWith(color: palette.caution),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: m.spaceSm),
            if (isActive)
              StatusPill(
                label: 'In use',
                tone: PillTone.normal,
                icon: Icons.check_circle,
                dense: true,
              )
            else if (isComplete)
              StatusPill(
                label: isSideloaded ? 'Loaded from file' : 'Installed',
                tone: PillTone.neutral,
                dense: true,
              )
            else
              Text(sizeLabel, style: context.texts.labelSmall),
          ],
        ),
        if (isInstalling && progress != null) ...<Widget>[
          SizedBox(height: m.spaceSm),
          LinearProgressIndicator(value: progress!.fraction),
          SizedBox(height: m.spaceXs),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${(progress!.receivedBytes / (1024 * 1024)).round()} of '
                  '${(progress!.totalBytes / (1024 * 1024)).round()} MB · '
                  '${progress!.currentFile}',
                  style: context.texts.labelSmall,
                ),
              ),
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ),
        ] else ...<Widget>[
          SizedBox(height: m.spaceSm),
          Row(
            children: <Widget>[
              if (!isComplete)
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onInstall,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(
                      partial
                          ? 'Resume — '
                              '${(bytesOnDisk / (1024 * 1024)).round()} of '
                              '$sizeLabel done'
                          : 'Install',
                    ),
                  ),
                )
              else if (onUse != null)
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onUse,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Use this one'),
                  ),
                )
              else if (isActive)
                Expanded(
                  child: Text(
                    isSideloaded ? '$activeLine Loaded from a file.' : activeLine,
                    style: context.texts.labelSmall,
                  ),
                ),
              if (onRemove != null) ...<Widget>[
                SizedBox(width: m.spaceSm),
                TextButton.icon(
                  onPressed: onRemove,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.critical,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
