import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/app_bootstrap.dart';

/// Press-to-record control that sits beside each free-text clinical field.
///
/// Dictation is offered here because during an examination the clinician's
/// hands are on the patient. The recording is stored as an attachment on the
/// note — it is evidence in its own right, not a throwaway input method.
class VoiceNoteButton extends StatefulWidget {
  const VoiceNoteButton({super.key, required this.onRecorded});

  final Future<void> Function(File file, Duration duration) onRecorded;

  @override
  State<VoiceNoteButton> createState() => _VoiceNoteButtonState();
}

class _VoiceNoteButtonState extends State<VoiceNoteButton> {
  Timer? _ticker;
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  bool _busy = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);

    final service = context.read<AppBootstrap>().voiceNotes;

    if (!_recording) {
      final started = await service.start();
      if (!mounted) return;
      if (!started) {
        setState(() => _busy = false);
        OptToast.error(context, 'Microphone permission is needed to dictate.');
        return;
      }
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed = service.elapsed);
      });
      setState(() {
        _recording = true;
        _busy = false;
        _elapsed = Duration.zero;
      });
      return;
    }

    _ticker?.cancel();
    final result = await service.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _elapsed = Duration.zero;
    });

    if (result != null) {
      await widget.onRecorded(result.file, result.duration);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (!_recording) {
      return IconButton(
        tooltip: 'Dictate a voice note',
        icon: const Icon(Icons.mic_none_outlined),
        onPressed: _busy ? null : _toggle,
      );
    }

    final seconds = _elapsed.inSeconds;
    return TextButton.icon(
      onPressed: _busy ? null : _toggle,
      icon: Icon(Icons.stop_circle_outlined, color: palette.critical),
      label: Text(
        '${(seconds ~/ 60)}:${(seconds % 60).toString().padLeft(2, '0')}',
        style: context.texts.labelMedium?.copyWith(color: palette.critical),
      ),
    );
  }
}
