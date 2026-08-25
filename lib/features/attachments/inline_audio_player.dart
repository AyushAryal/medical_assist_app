import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/design/design.dart';


/// A compact audio player that sits directly under the field it belongs to.
///
/// Dictation is only useful if it can be replayed where it was recorded — a
/// voice note filed away under "attachments" is a voice note nobody listens
/// to. This is deliberately small enough to live inline beneath a text field.
class InlineAudioPlayer extends StatefulWidget {
  const InlineAudioPlayer({
    super.key,
    required this.filePath,
    required this.label,
    this.onTranscribe,
    this.isTranscribing = false,
    this.durationMs,
    this.onDelete,
  });

  final String filePath;
  final String label;
  final int? durationMs;
  final VoidCallback? onDelete;

  /// Turns this recording into text. Null when no speech model is installed.
  final VoidCallback? onTranscribe;

  /// True while this recording is being transcribed.
  final bool isTranscribing;

  @override
  State<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSubscription;
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // Rewind on completion, rather than leaving the playhead parked at the
    // end. `just_audio` stops there and stays there, which leaves a fully
    // filled waveform and a full-length timestamp — a widget that looks spent
    // rather than one that can be played again. Resetting makes the replay
    // affordance visible instead of implied by an icon.
    _stateSubscription = _player.playerStateStream.listen((state) async {
      if (state.processingState != ProcessingState.completed) return;
      await _player.pause();
      await _player.seek(Duration.zero);
    });
    _open();
  }

  Future<void> _open() async {
    try {
      await _player.setFilePath(widget.filePath);
      if (mounted) setState(() => _ready = true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    _player.dispose();
    super.dispose();
  }

  static String _clock(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    if (_error != null) {
      return _Shell(
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, size: 16, color: palette.critical),
            SizedBox(width: m.spaceSm),
            Expanded(
              child: Text(
                'Recording could not be opened',
                style: context.texts.bodySmall?.copyWith(color: palette.critical),
              ),
            ),
          ],
        ),
      );
    }

    final fallback = widget.durationMs == null
        ? Duration.zero
        : Duration(milliseconds: widget.durationMs!);

    return _Shell(
      child: StreamBuilder<PlayerState>(
        stream: _player.playerStateStream,
        builder: (context, stateSnapshot) {
          final playing = stateSnapshot.data?.playing ?? false;
          final completed =
              stateSnapshot.data?.processingState == ProcessingState.completed;

          return StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, positionSnapshot) {
              final total = _player.duration ?? fallback;
              // Not pinned to `total` on completion any more: the listener in
              // initState rewinds, and holding the bar full for the frame in
              // between produced a visible flash of a spent widget.
              final position = positionSnapshot.data ?? Duration.zero;
              final progress = total.inMilliseconds == 0
                  ? 0.0
                  : (position.inMilliseconds / total.inMilliseconds)
                      .clamp(0.0, 1.0);

              return Row(
                children: <Widget>[
                  IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: !_ready
                        ? null
                        : () async {
                            if (playing) {
                              await _player.pause();
                            } else {
                              // Restart from wherever the playhead sits, which
                              // after a finished playback is the beginning.
                              if (completed) await _player.seek(Duration.zero);
                              await _player.play();
                            }
                          },
                  ),
                  SizedBox(width: m.spaceSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelMedium,
                        ),
                        SizedBox(height: m.spaceXs),
                        // A waveform scrubber rather than a progress bar.
                        // Recording length is what a listener judges by —
                        // "is this ten seconds or four minutes" — and a bar
                        // answers that far less immediately than a shape does.
                        PlaybackWaveform(
                          progress: progress,
                          playing: playing,
                          seed: widget.filePath,
                          onSeek: !_ready || total.inMilliseconds == 0
                              ? null
                              : (fraction) => _player.seek(
                                    Duration(
                                      milliseconds:
                                          (total.inMilliseconds * fraction)
                                              .round(),
                                    ),
                                  ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: m.spaceSm),
                  Text(
                    '${_clock(position)} / ${_clock(total)}',
                    style: context.texts.labelSmall?.copyWith(
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  if (widget.isTranscribing)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: m.spaceSm),
                      child: const AiSparkleIcon(size: 18),
                    )
                  else if (widget.onTranscribe != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      tooltip: 'Transcribe this recording',
                      icon: const Icon(Icons.auto_awesome_outlined),
                      onPressed: widget.onTranscribe,
                    ),
                  if (widget.onDelete != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      tooltip: 'Remove recording',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: widget.onDelete,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: m.spaceSm,
        vertical: m.spaceXs,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      child: child,
    );
  }
}
