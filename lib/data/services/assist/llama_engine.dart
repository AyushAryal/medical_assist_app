import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'language_model.dart';

/// The four-function C surface of `libclinical_llm.so`.
///
/// This is the entire native contract. It is flat on purpose — see the note
/// atop `native/llm_shim/clinical_llm.c`: binding llama.cpp's own structs from
/// Dart means mirroring layouts that change between releases, and a wrong
/// offset misreads memory instead of erroring. Four functions over `void*`,
/// `char*` and scalars cannot be wrong about layout.
final class _Shim {
  _Shim(DynamicLibrary library)
      : load = library.lookupFunction<
            Pointer<Void> Function(Pointer<Utf8>, Int32, Int32),
            Pointer<Void> Function(Pointer<Utf8>, int, int)>(
          'clinical_llm_load',
        ),
        free = library.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('clinical_llm_free'),
        complete = library.lookupFunction<
            Pointer<Utf8> Function(
                Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Int32, Float),
            Pointer<Utf8> Function(
                Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int, double)>(
          'clinical_llm_complete',
        ),
        freeText = library.lookupFunction<Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)>('clinical_llm_free_text');

  final Pointer<Void> Function(Pointer<Utf8> path, int nCtx, int nThreads)
      load;
  final void Function(Pointer<Void>) free;
  final Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8> system,
      Pointer<Utf8> user, int maxTokens, double temperature) complete;
  final void Function(Pointer<Utf8>) freeText;
}

/// One request into the worker isolate.
class _Job {
  const _Job({
    required this.id,
    required this.system,
    required this.user,
    required this.maxTokens,
    required this.temperature,
  });

  final int id;
  final String system;
  final String user;
  final int maxTokens;
  final double temperature;
}

/// A local language model, running in its own isolate.
///
/// An isolate rather than an async veneer, because the underlying C call
/// *blocks* — a 1B-parameter model on tablet CPUs takes seconds per answer,
/// and seconds of frozen UI in a clinical app is a defect, not a latency. The
/// model handle lives entirely inside the worker (FFI pointers must not cross
/// isolates); this class only passes strings.
///
/// Everything here honours the governance rules in `language_model.dart`: it
/// loads a file from this device and talks to nothing else, every output is a
/// draft, and the assistant path only ever asks it to *rewrite* — the prompt
/// built in [rephraseAsKnownQuestion] carries the published question bank and
/// nothing about any patient.
class LlamaEngine implements LanguageModelEngine {
  LlamaEngine({
    required this.modelPath,
    required String modelName,
    this.libraryPath,
    this.threads = 4,
  }) : name = modelName;

  /// Absolute path to the GGUF file.
  final String modelPath;

  @override
  final String name;

  /// Override for tests, which load the host build of the shim. On Android
  /// the library ships in the APK and the linker finds it by name.
  final String? libraryPath;

  final int threads;

  @override
  bool get runsOnDevice => true;

  Isolate? _isolate;
  SendPort? _commands;
  final Map<int, Completer<String?>> _pending = <int, Completer<String?>>{};
  int _nextId = 0;
  bool _failed = false;

  @override
  Future<bool> isReady() async {
    if (_failed) return false;
    return File(modelPath).exists();
  }

  Future<SendPort?> _ensureWorker() async {
    if (_failed) return null;
    if (_commands != null) return _commands;

    final handshake = ReceivePort();
    try {
      _isolate = await Isolate.spawn(
        _worker,
        (
          reply: handshake.sendPort,
          modelPath: modelPath,
          libraryPath: libraryPath,
          threads: threads,
        ),
        debugName: 'clinical-llm',
      );
    } on Object {
      _failed = true;
      handshake.close();
      return null;
    }

    final first = await handshake.first;
    handshake.close();
    if (first is! SendPort) {
      // The worker could not load the library or the model. Failed is sticky:
      // retrying a load that just failed on the same file gives the same
      // answer at the same multi-second price.
      _failed = true;
      return null;
    }
    _commands = first;

    final results = ReceivePort();
    _commands!.send(results.sendPort);
    results.listen((message) {
      if (message is (int, String?)) {
        _pending.remove(message.$1)?.complete(message.$2);
      }
    });
    return _commands;
  }

  Future<String?> _complete(
    String system,
    String user, {
    int maxTokens = 64,
    double temperature = 0,
  }) async {
    final commands = await _ensureWorker();
    if (commands == null) return null;

    final id = _nextId++;
    final completer = Completer<String?>();
    _pending[id] = completer;
    commands.send(_Job(
      id: id,
      system: system,
      user: user,
      maxTokens: maxTokens,
      temperature: temperature,
    ));
    return completer.future;
  }

  @override
  Future<String?> rephraseAsKnownQuestion(
    String request, {
    required List<String> vocabulary,
  }) async {
    final answer = await _complete(
      'You translate a clinician\'s request about their patient register '
      'into EXACTLY ONE question from the supported list below, copied '
      'character for character. Reply with that single question and nothing '
      'else — no quotes, no explanation. Never repeat the request itself. '
      'If no supported question means what the request means, reply exactly '
      'NONE.\n\nSupported questions:\n'
      '${vocabulary.map((q) => '- $q').join('\n')}\n\n'
      'Remember: one supported question verbatim, or NONE.',
      request,
      maxTokens: 40,
    );
    if (answer == null) return null;

    final cleaned = answer
        .trim()
        .replaceAll(RegExp(r'^["\x27`\-\s]+|["\x27`.\s]+$'), '')
        .trim();
    if (cleaned.isEmpty || cleaned.length > 120) return null;
    if (cleaned.toUpperCase() == 'NONE') return null;
    // An echo is not a translation. Small models under a "copy exactly"
    // instruction sometimes copy the wrong thing — the request — and handing
    // that back would put the untranslatable wording through the grammars a
    // second time, at model prices, for the same refusal.
    if (cleaned.toLowerCase() == request.trim().toLowerCase()) return null;
    return cleaned;
  }

  @override
  Future<LanguageModelDraft> structureDictation(String transcript) async {
    final answer = await _complete(
      'Sort the clinician\'s dictated sentences into the four SOAP sections. '
      'Use every sentence exactly once, word for word. Add nothing, '
      'summarise nothing, diagnose nothing. Reply in exactly this format:\n'
      'SUBJECTIVE:\n...\nOBJECTIVE:\n...\nASSESSMENT:\n...\nPLAN:\n...',
      transcript,
      maxTokens: 512,
    );
    return _draft(answer ?? transcript, sections: _soap(answer));
  }

  @override
  Future<LanguageModelDraft> plainLanguageInstructions(String plan) async {
    final answer = await _complete(
      'Rewrite this clinical plan as short instructions the patient can '
      'follow at home, in plain words. Keep every instruction; add none.',
      plan,
      maxTokens: 384,
    );
    return _draft(answer ?? plan);
  }

  LanguageModelDraft _draft(String text, {Map<String, String>? sections}) =>
      LanguageModelDraft(
        text: text,
        engineName: name,
        sections: sections ?? const <String, String>{},
      );

  static Map<String, String> _soap(String? answer) {
    if (answer == null) return const <String, String>{};
    final sections = <String, String>{};
    final pattern = RegExp(
      r'(SUBJECTIVE|OBJECTIVE|ASSESSMENT|PLAN):\s*',
      caseSensitive: false,
    );
    final matches = pattern.allMatches(answer).toList();
    for (var i = 0; i < matches.length; i++) {
      final end =
          i + 1 < matches.length ? matches[i + 1].start : answer.length;
      final body = answer.substring(matches[i].end, end).trim();
      if (body.isNotEmpty) {
        sections[matches[i].group(1)!.toLowerCase()] = body;
      }
    }
    return sections;
  }

  @override
  Future<void> dispose() async {
    _commands?.send(null);
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _commands = null;
    for (final pending in _pending.values) {
      pending.complete(null);
    }
    _pending.clear();
  }

  /// The worker. Owns every native handle; nothing FFI crosses back.
  static void _worker(
    ({
      SendPort reply,
      String modelPath,
      String? libraryPath,
      int threads,
    }) boot,
  ) {
    final _Shim shim;
    final Pointer<Void> handle;
    try {
      final library = boot.libraryPath != null
          ? DynamicLibrary.open(boot.libraryPath!)
          : DynamicLibrary.open('libclinical_llm.so');
      shim = _Shim(library);

      final path = boot.modelPath.toNativeUtf8();
      // 2048 tokens of context: the rewrite prompt is ~1k with the full
      // question bank, the answer a single line. Small context keeps the
      // KV cache in tens of megabytes instead of hundreds.
      handle = shim.load(path, 2048, boot.threads);
      malloc.free(path);
      if (handle == nullptr) {
        boot.reply.send('model-load-failed');
        return;
      }
    } on Object catch (error) {
      boot.reply.send('library-load-failed: $error');
      return;
    }

    final commands = ReceivePort();
    boot.reply.send(commands.sendPort);
    SendPort? results;

    commands.listen((message) {
      if (message is SendPort) {
        results = message;
        return;
      }
      if (message is _Job) {
        final system = message.system.toNativeUtf8();
        final user = message.user.toNativeUtf8();
        final answer = shim.complete(
          handle,
          system,
          user,
          message.maxTokens,
          message.temperature,
        );
        malloc.free(system);
        malloc.free(user);

        String? text;
        if (answer != nullptr) {
          text = answer.toDartString();
          shim.freeText(answer);
        }
        results?.send((message.id, text));
        return;
      }
      // null: shut down.
      shim.free(handle);
      commands.close();
    });
  }
}
