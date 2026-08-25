import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../model_download.dart';
import 'assist_model_catalog.dart';

/// Where an installed assistant model lives on this device.
typedef InstalledAssistModel = ({AssistModel model, String path});

/// Installs, finds and removes the assistant's language models.
///
/// Same shape and same rules as the speech models, sharing the same download
/// machinery: files land in application support (a replaceable cache, not
/// user data), a size mismatch is refused rather than loaded, and the
/// side-load directory under `Android/data/<package>/files` provisions an
/// airgapped device with one `adb push`.
class AssistModelManager {
  // A named parameter may not begin with an underscore, so a private field
  // can never be filled by an initializing formal — same note as the speech
  // manager.
  // ignore_for_file: prefer_initializing_formals
  AssistModelManager({Directory? root, HttpClient? client})
      : _root = root,
        _client = client;

  final Directory? _root;
  final HttpClient? _client;

  static const String folderName = 'assist_models';

  Directory? _resolved;
  Directory? _resolvedExternal;
  bool _triedExternal = false;

  Future<Directory> _modelsDirectory() async {
    if (_resolved != null) return _resolved!;
    final base = _root ?? await getApplicationSupportDirectory();
    final directory = Directory(p.join(base.path, folderName));
    if (!await directory.exists()) await directory.create(recursive: true);
    _resolved = directory;
    return directory;
  }

  Future<Directory?> _externalModelsDirectory() async {
    if (_triedExternal) return _resolvedExternal;
    _triedExternal = true;
    if (_root != null) return null;
    try {
      final base = await getExternalStorageDirectory();
      if (base == null) return null;
      _resolvedExternal = Directory(p.join(base.path, folderName));
    } on Object {
      _resolvedExternal = null;
    }
    return _resolvedExternal;
  }

  Future<List<Directory>> _searchRoots() async => <Directory>[
        await _modelsDirectory(),
        ?await _externalModelsDirectory(),
      ];

  Future<Directory> directoryFor(AssistModel model) async =>
      Directory(p.join((await _modelsDirectory()).path, model.id));

  /// The exact path to `adb push` to, for the UI to display.
  Future<String?> sideloadPathFor(AssistModel model) async {
    final external = await _externalModelsDirectory();
    return external == null ? null : p.join(external.path, model.id);
  }

  /// The model's file, only if present at exactly the size it should be.
  /// A truncated GGUF crashes inside C++ on load; refusing it here keeps a
  /// bad download from looking like a broken app.
  Future<InstalledAssistModel?> installed(AssistModel model) async {
    for (final root in await _searchRoots()) {
      final file = File(p.join(root.path, model.id, model.file));
      if (await file.exists() && await file.length() == model.bytes) {
        return (model: model, path: file.path);
      }
    }
    return null;
  }

  Future<AssistModel?> firstInstalled() async {
    for (final model in AssistModelCatalog.models) {
      if (await installed(model) != null) return model;
    }
    return null;
  }

  /// Bytes already on disk, so an interrupted install reports "310 of 491 MB"
  /// instead of starting from zero.
  Future<int> bytesOnDisk(AssistModel model) async {
    var best = 0;
    for (final root in await _searchRoots()) {
      final directory = Directory(p.join(root.path, model.id));
      if (!await directory.exists()) continue;
      var total = 0;
      await for (final entity in directory.list()) {
        if (entity is File) total += await entity.length();
      }
      if (total > best) best = total;
    }
    return best;
  }

  Future<void> download(
    AssistModel model, {
    void Function(ModelInstallProgress)? onProgress,
    CancellationToken? cancellation,
  }) async {
    await downloadArtefacts(
      into: await directoryFor(model),
      artefacts: <ModelArtefact>[
        (url: model.url, file: model.file, bytes: model.bytes, sizePinned: true),
      ],
      totalBytes: model.bytes,
      client: _client,
      userAgent: 'ClinicalRecords/assist-model-installer',
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }

  /// Deletes every copy, wherever it was installed from — removing only the
  /// internal one would leave a pushed copy silently keeping the feature on.
  Future<void> remove(AssistModel model) async {
    for (final root in await _searchRoots()) {
      final directory = Directory(p.join(root.path, model.id));
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }
}
