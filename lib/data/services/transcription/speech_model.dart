import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A Whisper model this app knows how to install and run.
///
/// Only int8-quantised `tiny` variants are offered. `base` and above are more
/// accurate but need roughly four times the memory and run slower than real
/// time on the mid-range Android hardware this app is built for, and a
/// transcription that arrives after the patient has left is not a feature.
class SpeechModel {
  const SpeechModel({
    required this.id,
    required this.name,
    required this.description,
    required this.repository,
    required this.encoderFile,
    required this.decoderFile,
    required this.tokensFile,
    required this.encoderBytes,
    required this.decoderBytes,
    required this.tokensBytes,
    required this.isMultilingual,
  });

  final String id;
  final String name;
  final String description;

  /// Hugging Face repository holding the converted ONNX files.
  final String repository;

  final String encoderFile;
  final String decoderFile;
  final String tokensFile;

  /// Exact sizes, so the download shows real progress and can refuse to start
  /// when the device has no room — discovering that halfway through a 100 MB
  /// download on a clinic's metered connection is not acceptable.
  final int encoderBytes;
  final int decoderBytes;
  final int tokensBytes;

  final bool isMultilingual;

  int get totalBytes => encoderBytes + decoderBytes + tokensBytes;

  String get sizeLabel => '${(totalBytes / (1024 * 1024)).round()} MB';

  List<({String file, int bytes})> get files => <({String file, int bytes})>[
        (file: tokensFile, bytes: tokensBytes),
        (file: encoderFile, bytes: encoderBytes),
        (file: decoderFile, bytes: decoderBytes),
      ];

  String urlFor(String file) =>
      'https://huggingface.co/$repository/resolve/main/$file';

  /// English-only, and the fastest option. The `.en` models are meaningfully
  /// more accurate than multilingual `tiny` on English speech at the same size,
  /// because none of their capacity is spent on other languages.
  static const SpeechModel tinyEn = SpeechModel(
    id: 'whisper-tiny-en',
    name: 'Whisper tiny (English)',
    description: 'English only. The fastest option and the most accurate of '
        'the two on English speech.',
    repository: 'csukuangfj/sherpa-onnx-whisper-tiny.en',
    encoderFile: 'tiny.en-encoder.int8.onnx',
    decoderFile: 'tiny.en-decoder.int8.onnx',
    tokensFile: 'tiny.en-tokens.txt',
    encoderBytes: 12937772,
    decoderBytes: 89853865,
    tokensBytes: 835554,
    isMultilingual: false,
  );

  static const SpeechModel tinyMultilingual = SpeechModel(
    id: 'whisper-tiny',
    name: 'Whisper tiny (multilingual)',
    description: 'Around 99 languages, at some cost to English accuracy. '
        'Choose this where consultations are not conducted in English.',
    repository: 'csukuangfj/sherpa-onnx-whisper-tiny',
    encoderFile: 'tiny-encoder.int8.onnx',
    decoderFile: 'tiny-decoder.int8.onnx',
    tokensFile: 'tiny-tokens.txt',
    encoderBytes: 12937772,
    decoderBytes: 89855401,
    tokensBytes: 816730,
    isMultilingual: true,
  );

  static const List<SpeechModel> all = <SpeechModel>[tinyEn, tinyMultilingual];

  static SpeechModel? byId(String? id) =>
      all.where((model) => model.id == id).firstOrNull;
}

/// Where an installed model's three files live on this device.
class InstalledModel {
  const InstalledModel({
    required this.model,
    required this.encoderPath,
    required this.decoderPath,
    required this.tokensPath,
  });

  final SpeechModel model;
  final String encoderPath;
  final String decoderPath;
  final String tokensPath;
}

/// Progress of an install, for a UI that must stay honest about a long job.
class ModelInstallProgress {
  const ModelInstallProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.currentFile,
  });

  final int receivedBytes;
  final int totalBytes;
  final String currentFile;

  double get fraction =>
      totalBytes == 0 ? 0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

/// Installs, finds and removes speech models.
///
/// **This class holds the only outbound network code in the application**, and
/// that is a deliberate, contained exception rather than a softening of the
/// offline-first design. What it fetches is a public, static model file. It
/// sends no patient data, no identifiers and no telemetry, it runs only when a
/// user taps Install, and [importFromFile] exists so a device that must never
/// touch a network can be provisioned by hand instead.
///
/// If that exception is unacceptable for a deployment, deleting this file
/// disables the download path and leaves side-loading working.
class SpeechModelManager {
  /// [root] and [client] are injection points for tests; production callers
  /// pass neither.
  //
  // The lint asking for `this._root` cannot be satisfied: a named parameter may
  // not begin with an underscore, so a private field can never be filled by an
  // initializing formal.
  // ignore_for_file: prefer_initializing_formals
  SpeechModelManager({Directory? root, HttpClient? client})
      : _root = root,
        _client = client;

  final Directory? _root;
  final HttpClient? _client;

  Directory? _resolved;
  Directory? _resolvedExternal;
  bool _triedExternal = false;

  /// The subdirectory name used under every search root.
  static const String folderName = 'speech_models';

  Future<Directory> _modelsDirectory() async {
    if (_resolved != null) return _resolved!;
    final base = _root ?? await getApplicationSupportDirectory();
    // Application support rather than documents: these are replaceable caches,
    // not user data, and they must not appear in a file browser or be swept
    // into a device backup.
    final directory = Directory(p.join(base.path, folderName));
    if (!await directory.exists()) await directory.create(recursive: true);
    _resolved = directory;
    return directory;
  }

  /// The app's own directory on external storage, if the platform has one.
  ///
  /// This is the provisioning route for a device that must never reach a
  /// network, and it is the only one that needs neither root nor a runtime
  /// permission: `adb push` can write into `Android/data/<package>/files`, and
  /// an app can read its own directory there without asking for anything. So a
  /// model can be placed on a device from a laptop in one command and is picked
  /// up on the next launch.
  ///
  /// Returns null on iOS, which has no equivalent, and when a test supplies its
  /// own root.
  Future<Directory?> _externalModelsDirectory() async {
    if (_triedExternal) return _resolvedExternal;
    _triedExternal = true;
    if (_root != null) return null;
    try {
      final base = await getExternalStorageDirectory();
      if (base == null) return null;
      _resolvedExternal = Directory(p.join(base.path, folderName));
    } on Object {
      // Unsupported platform, or no external storage mounted. Not an error —
      // the internal directory is the normal case.
      _resolvedExternal = null;
    }
    return _resolvedExternal;
  }

  /// Every place a model may live, in the order they are searched.
  ///
  /// The internal directory comes first because it is where downloads and
  /// imports land, so a locally installed model wins over a stale pushed one.
  Future<List<Directory>> searchRoots() async {
    return <Directory>[
      await _modelsDirectory(),
      ?await _externalModelsDirectory(),
    ];
  }

  /// Where downloads and imports are written.
  Future<Directory> directoryFor(SpeechModel model) async {
    final root = await _modelsDirectory();
    return Directory(p.join(root.path, model.id));
  }

  /// The exact path to push files to, for the UI to display. Null where the
  /// platform has no external storage.
  Future<String?> sideloadPathFor(SpeechModel model) async {
    final external = await _externalModelsDirectory();
    return external == null ? null : p.join(external.path, model.id);
  }

  /// Returns the model only if all three files are present **and** the two
  /// large ones are the size they should be.
  ///
  /// Checking size matters: an interrupted download leaves a truncated ONNX
  /// file, and the native loader's response to one is a crash inside a C++
  /// library rather than a Dart exception. Refusing to load it here is what
  /// keeps a bad download from looking like a broken app.
  Future<InstalledModel?> installed(SpeechModel model) async {
    for (final root in await searchRoots()) {
      final found = await _installedUnder(
        Directory(p.join(root.path, model.id)),
        model,
      );
      if (found != null) return found;
    }
    return null;
  }

  Future<InstalledModel?> _installedUnder(
    Directory directory,
    SpeechModel model,
  ) async {
    if (!await directory.exists()) return null;

    final encoder = File(p.join(directory.path, model.encoderFile));
    final decoder = File(p.join(directory.path, model.decoderFile));
    final tokens = File(p.join(directory.path, model.tokensFile));

    for (final file in <File>[encoder, decoder, tokens]) {
      if (!await file.exists()) return null;
    }
    if (await encoder.length() != model.encoderBytes) return null;
    if (await decoder.length() != model.decoderBytes) return null;
    if (await tokens.length() == 0) return null;

    return InstalledModel(
      model: model,
      encoderPath: encoder.path,
      decoderPath: decoder.path,
      tokensPath: tokens.path,
    );
  }

  /// Where the installed copy actually came from, for the UI to report. A
  /// pushed model and a downloaded one behave identically but it is worth
  /// saying which is in use.
  Future<bool> isSideloaded(SpeechModel model) async {
    final internal = await _installedUnder(
      Directory(p.join((await _modelsDirectory()).path, model.id)),
      model,
    );
    if (internal != null) return false;
    return await installed(model) != null;
  }

  Future<SpeechModel?> firstInstalled() async {
    for (final model in SpeechModel.all) {
      if (await installed(model) != null) return model;
    }
    return null;
  }

  /// Bytes already on disk for a partially installed model, so the UI can say
  /// "62 of 104 MB" rather than starting from zero after an interruption.
  Future<int> bytesOnDisk(SpeechModel model) async {
    var best = 0;
    for (final root in await searchRoots()) {
      final directory = Directory(p.join(root.path, model.id));
      if (!await directory.exists()) continue;
      var total = 0;
      await for (final entity in directory.list()) {
        if (entity is File) total += await entity.length();
      }
      // The largest single copy, not the sum: two half-installs in two places
      // do not add up to one working model, and reporting them as though they
      // did would show a progress bar past 100%.
      if (total > best) best = total;
    }
    return best;
  }

  /// Downloads any of the model's files that are missing or the wrong size.
  ///
  /// Files are written to a `.part` path and renamed on completion, so an
  /// interrupted install can never leave a truncated file that [installed]
  /// would go on to accept.
  Future<void> download(
    SpeechModel model, {
    void Function(ModelInstallProgress)? onProgress,
    CancellationToken? cancellation,
  }) async {
    final directory = await directoryFor(model);
    if (!await directory.exists()) await directory.create(recursive: true);

    final client = _client ?? HttpClient();
    client.userAgent = 'ClinicalRecords/speech-model-installer';
    var completed = 0;

    try {
      for (final entry in model.files) {
        final target = File(p.join(directory.path, entry.file));
        if (await target.exists() && await target.length() == entry.bytes) {
          completed += entry.bytes;
          onProgress?.call(
            ModelInstallProgress(
              receivedBytes: completed,
              totalBytes: model.totalBytes,
              currentFile: entry.file,
            ),
          );
          continue;
        }

        final partial = File('${target.path}.part');
        if (await partial.exists()) await partial.delete();

        final request = await client.getUrl(Uri.parse(model.urlFor(entry.file)));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw ModelInstallException(
            'The server returned ${response.statusCode} for ${entry.file}.',
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
            onProgress?.call(
              ModelInstallProgress(
                receivedBytes: completed + received,
                totalBytes: model.totalBytes,
                currentFile: entry.file,
              ),
            );
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        // The tokens file is small and its size is not pinned; the two model
        // files are, and a mismatch means a truncated or substituted download.
        if (entry.bytes > 1024 * 1024 && received != entry.bytes) {
          await partial.delete();
          throw ModelInstallException(
            '${entry.file} downloaded as $received bytes but should be '
            '${entry.bytes}. The file was discarded.',
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
      if (_client == null) client.close();
    }
  }

  /// Installs a file the operator supplied themselves — the airgapped path.
  ///
  /// The file is matched to a model by name and size rather than by asking the
  /// operator which one it is, because getting that answer wrong produces a
  /// native crash on load rather than a clear error.
  Future<SpeechModelImport> importFromFile(File source) async {
    if (!await source.exists()) {
      return const SpeechModelImport.rejected('That file no longer exists.');
    }

    final name = p.basename(source.path);
    final size = await source.length();

    for (final model in SpeechModel.all) {
      for (final entry in model.files) {
        if (entry.file != name) continue;
        // The tokens file's size is not pinned; the model files' are.
        if (entry.bytes > 1024 * 1024 && size != entry.bytes) {
          return SpeechModelImport.rejected(
            '$name is $size bytes but ${model.name} expects ${entry.bytes}. '
            'This looks like a different build of the model.',
          );
        }

        final directory = await directoryFor(model);
        if (!await directory.exists()) await directory.create(recursive: true);
        await source.copy(p.join(directory.path, name));

        final complete = await installed(model) != null;
        return SpeechModelImport.accepted(
          model: model,
          fileName: name,
          isComplete: complete,
        );
      }
    }

    return SpeechModelImport.rejected(
      '$name is not one of the files a speech model is made of. Expected one '
      'of: ${SpeechModel.all.expand((m) => m.files.map((f) => f.file)).join(', ')}.',
    );
  }

  /// Deletes every copy, wherever it was installed from.
  ///
  /// Removing only the internal copy would silently leave a pushed one in
  /// place, and the feature would appear not to turn off.
  Future<void> remove(SpeechModel model) async {
    for (final root in await searchRoots()) {
      final directory = Directory(p.join(root.path, model.id));
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }
}

class SpeechModelImport {
  const SpeechModelImport.accepted({
    required this.model,
    required this.fileName,
    required this.isComplete,
  })  : accepted = true,
        problem = null;

  const SpeechModelImport.rejected(String this.problem)
      : accepted = false,
        model = null,
        fileName = null,
        isComplete = false;

  final bool accepted;
  final SpeechModel? model;
  final String? fileName;

  /// True once all three of the model's files are present.
  final bool isComplete;
  final String? problem;
}

class ModelInstallException implements Exception {
  const ModelInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lets a long download be abandoned when the user leaves the screen.
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}
