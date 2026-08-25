import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/utils/ids.dart';

/// Records dictation into a temporary file for the caller to attach.
///
/// Recording sits next to the free-text clinical fields because a clinician
/// mid-examination has hands and eyes on the patient, not on a keyboard. The
/// audio is kept alongside any future transcript — a transcription is an
/// interpretation, and the original recording is what the record falls back on.
class VoiceNoteService {
  VoiceNoteService([AudioRecorder? recorder])
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  DateTime? _startedAt;
  String? _activePath;

  bool get isRecording => _activePath != null;

  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// AAC in an m4a container: broadly playable, and roughly a tenth the size
  /// of WAV, which matters on a device holding a whole clinic's records.
  Future<bool> start() async {
    if (isRecording) return true;
    if (!await _recorder.hasPermission()) return false;

    final directory = await getTemporaryDirectory();
    final path = p.join(directory.path, '${newId()}.m4a');

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );

    _activePath = path;
    _startedAt = DateTime.now();
    return true;
  }

  /// Returns the finished file, or null if nothing usable was captured.
  Future<({File file, Duration duration})?> stop() async {
    if (!isRecording) return null;
    final duration = elapsed;
    final path = await _recorder.stop();
    _activePath = null;
    _startedAt = null;

    if (path == null) return null;
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) return null;
    return (file: file, duration: duration);
  }

  /// Abandons the recording and removes the partial file.
  Future<void> cancel() async {
    if (!isRecording) return;
    final path = _activePath;
    await _recorder.stop();
    _activePath = null;
    _startedAt = null;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}
