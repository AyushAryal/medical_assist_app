import 'dart:io';

import 'package:path/path.dart' as p;

import 'transcription/speech_model.dart'
    show CancellationToken, ModelInstallException, ModelInstallProgress;

export 'transcription/speech_model.dart'
    show CancellationToken, ModelInstallException, ModelInstallProgress;

/// One file a model needs: where it comes from, what it must weigh.
typedef ModelArtefact = ({String url, String file, int bytes, bool sizePinned});

/// Downloads a model's files with the semantics both model families rely on.
///
/// Extracted from the speech-model manager the day a second family of models
/// (the assistant's GGUF files) needed the same behaviour, because these
/// semantics are exactly the kind that drift when copied:
///
/// * A file is written to a `.part` path and renamed only when complete, so
///   an interruption can never leave a truncated file that a later
///   "is it installed" check would accept — the native loader's response to a
///   truncated model is a crash inside C++, not a Dart exception.
/// * A size-pinned file that arrives at the wrong size is deleted and
///   reported, not kept: a substituted or clipped download must fail loudly.
/// * A file already present at the right size is skipped, so retrying an
///   interrupted install resumes instead of starting over.
Future<void> downloadArtefacts({
  required Directory into,
  required List<ModelArtefact> artefacts,
  required int totalBytes,
  HttpClient? client,
  String userAgent = 'ClinicalRecords/model-installer',
  void Function(ModelInstallProgress)? onProgress,
  CancellationToken? cancellation,
}) async {
  if (!await into.exists()) await into.create(recursive: true);

  final http = client ?? HttpClient();
  http.userAgent = userAgent;
  var completed = 0;

  try {
    for (final artefact in artefacts) {
      final target = File(p.join(into.path, artefact.file));
      if (await target.exists() && await target.length() == artefact.bytes) {
        completed += artefact.bytes;
        onProgress?.call(ModelInstallProgress(
          receivedBytes: completed,
          totalBytes: totalBytes,
          currentFile: artefact.file,
        ));
        continue;
      }

      final partial = File('${target.path}.part');
      if (await partial.exists()) await partial.delete();

      final request = await http.getUrl(Uri.parse(artefact.url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw ModelInstallException(
          'The server returned ${response.statusCode} for ${artefact.file}.',
        );
      }

      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          if (cancellation?.isCancelled ?? false) {
            throw const ModelInstallException('Install cancelled.');
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(ModelInstallProgress(
            receivedBytes: completed + received,
            totalBytes: totalBytes,
            currentFile: artefact.file,
          ));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (artefact.sizePinned && received != artefact.bytes) {
        await partial.delete();
        throw ModelInstallException(
          '${artefact.file} downloaded as $received bytes but should be '
          '${artefact.bytes}. The file was discarded.',
        );
      }

      await partial.rename(target.path);
      completed += received;
    }
  } on ModelInstallException {
    rethrow;
  } on SocketException catch (error) {
    throw ModelInstallException(
      'Could not reach the model host: ${error.message}',
    );
  } on HttpException catch (error) {
    throw ModelInstallException('Download failed: ${error.message}');
  } finally {
    if (client == null) http.close();
  }
}
