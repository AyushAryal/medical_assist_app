import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../data/services/model_download.dart';

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
                  Text(name, style: context.texts.titleSmall),
                  SizedBox(height: m.spaceXs / 2),
                  Text(description, style: context.texts.bodySmall),
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
