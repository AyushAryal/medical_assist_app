import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/data/services/transcription/speech_model.dart';
import 'package:path/path.dart' as p;

/// Covers the side-load path — the way a device that must never reach a
/// network gets a speech model. No HTTP is exercised here on purpose: these
/// tests must run offline, like everything else in this suite.
void main() {
  late Directory root;
  late SpeechModelManager manager;
  final model = SpeechModel.tinyEn;

  setUp(() {
    root = Directory.systemTemp.createTempSync('speech_model_test');
    manager = SpeechModelManager(root: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// A file of exactly the size the manager expects for [name].
  File fixture(String name, int bytes) {
    final file = File(p.join(root.path, name));
    file.writeAsBytesSync(List<int>.filled(bytes, 0));
    return file;
  }

  Future<void> installAll() async {
    await manager.importFromFile(fixture(model.tokensFile, 4096));
    await manager.importFromFile(
      fixture(model.encoderFile, model.encoderBytes),
    );
    await manager.importFromFile(
      fixture(model.decoderFile, model.decoderBytes),
    );
  }

  group('importFromFile', () {
    test('accepts a file it recognises by name and size', () async {
      final result = await manager.importFromFile(
        fixture(model.encoderFile, model.encoderBytes),
      );

      expect(result.accepted, isTrue);
      expect(result.model?.id, model.id);
      expect(result.isComplete, isFalse, reason: 'two files still missing');
    });

    test('reports completeness once all three files are present', () async {
      await manager.importFromFile(fixture(model.tokensFile, 4096));
      await manager.importFromFile(
        fixture(model.encoderFile, model.encoderBytes),
      );
      final last = await manager.importFromFile(
        fixture(model.decoderFile, model.decoderBytes),
      );

      expect(last.isComplete, isTrue);
    });

    test('rejects a model file of the wrong size', () async {
      // A truncated or substituted ONNX file crashes inside a C++ library on
      // load rather than throwing something Dart can catch, so it has to be
      // refused here.
      final result = await manager.importFromFile(
        fixture(model.encoderFile, model.encoderBytes - 1),
      );

      expect(result.accepted, isFalse);
      expect(result.problem, contains('different build'));
    });

    test('rejects a file that is not part of any model', () async {
      final result = await manager.importFromFile(
        fixture('holiday-photo.onnx', 2048),
      );

      expect(result.accepted, isFalse);
      expect(result.problem, contains('not one of the files'));
      // The message names what *is* expected, so the operator can find it.
      expect(result.problem, contains(model.encoderFile));
    });

    test('rejects a file that has gone away', () async {
      final missing = File(p.join(root.path, 'never-existed.onnx'));
      final result = await manager.importFromFile(missing);

      expect(result.accepted, isFalse);
    });

    test('does not size-check the tokens file, whose size is not pinned',
        () async {
      final result = await manager.importFromFile(
        fixture(model.tokensFile, 1234),
      );
      expect(result.accepted, isTrue);
    });
  });

  group('installed', () {
    test('is null until every file is present', () async {
      expect(await manager.installed(model), isNull);

      await manager.importFromFile(
        fixture(model.encoderFile, model.encoderBytes),
      );
      expect(await manager.installed(model), isNull);
    });

    test('returns resolved paths once complete', () async {
      await installAll();

      final installed = await manager.installed(model);
      expect(installed, isNotNull);
      expect(File(installed!.encoderPath).existsSync(), isTrue);
      expect(File(installed.decoderPath).existsSync(), isTrue);
      expect(File(installed.tokensPath).existsSync(), isTrue);
    });

    test('refuses a truncated file that reached the directory anyway',
        () async {
      await installAll();
      // Simulate an interrupted download that left a short file behind.
      File(p.join((await manager.directoryFor(model)).path, model.encoderFile))
          .writeAsBytesSync(<int>[1, 2, 3]);

      expect(await manager.installed(model), isNull);
    });

    test('an empty tokens file is not a usable install', () async {
      await installAll();
      File(p.join((await manager.directoryFor(model)).path, model.tokensFile))
          .writeAsBytesSync(<int>[]);

      expect(await manager.installed(model), isNull);
    });
  });

  group('search roots', () {
    test('a test-supplied root is the only place searched', () async {
      // Guards the injection point: if external storage leaked in here the
      // tests would depend on the host machine's filesystem.
      expect(await manager.searchRoots(), hasLength(1));
      expect(await manager.sideloadPathFor(model), isNull);
    });

    test('a model in the primary root is not reported as side-loaded',
        () async {
      await installAll();
      expect(await manager.isSideloaded(model), isFalse);
    });

    test('the models folder name is stable', () {
      // The provisioning script pushes to this path, so renaming it silently
      // breaks every already-provisioned device.
      expect(SpeechModelManager.folderName, 'speech_models');
    });
  });

  group('housekeeping', () {
    test('firstInstalled finds a complete model and ignores a partial one',
        () async {
      await manager.importFromFile(
        fixture(
          SpeechModel.tinyMultilingual.encoderFile,
          SpeechModel.tinyMultilingual.encoderBytes,
        ),
      );
      expect(await manager.firstInstalled(), isNull);

      await installAll();
      expect((await manager.firstInstalled())?.id, model.id);
    });

    test('bytesOnDisk reports progress toward a complete install', () async {
      expect(await manager.bytesOnDisk(model), 0);

      await manager.importFromFile(
        fixture(model.encoderFile, model.encoderBytes),
      );
      expect(await manager.bytesOnDisk(model), model.encoderBytes);
    });

    test('bytesOnDisk never exceeds the model size', () async {
      // It reports the largest single copy rather than the sum across search
      // roots: two half-installs in two places are not one working model, and
      // adding them would drive a progress bar past 100%.
      await installAll();
      expect(
        await manager.bytesOnDisk(model),
        lessThanOrEqualTo(model.totalBytes),
      );
    });

    test('remove deletes the model and leaves others alone', () async {
      await installAll();
      await manager.importFromFile(
        fixture(
          SpeechModel.tinyMultilingual.tokensFile,
          2048,
        ),
      );

      await manager.remove(model);

      expect(await manager.installed(model), isNull);
      expect(await manager.bytesOnDisk(model), 0);
      expect(
        await manager.bytesOnDisk(SpeechModel.tinyMultilingual),
        greaterThan(0),
      );
    });

    test('removing a model that was never installed is not an error',
        () async {
      await manager.remove(model);
      expect(await manager.bytesOnDisk(model), 0);
    });
  });

  group('model catalogue', () {
    test('every model declares three distinct files and a real size', () {
      for (final model in SpeechModel.all) {
        expect(model.files, hasLength(3));
        expect(
          model.files.map((f) => f.file).toSet(),
          hasLength(3),
          reason: '${model.id} has duplicate file names',
        );
        expect(model.totalBytes, greaterThan(10 * 1024 * 1024));
        expect(model.sizeLabel, contains('MB'));
      }
    });

    test('urls point at the declared repository', () {
      expect(
        SpeechModel.tinyEn.urlFor(SpeechModel.tinyEn.encoderFile),
        'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/'
        'resolve/main/tiny.en-encoder.int8.onnx',
      );
    });

    test('byId round-trips and rejects an unknown id', () {
      expect(SpeechModel.byId(SpeechModel.tinyEn.id), SpeechModel.tinyEn);
      expect(SpeechModel.byId('not-a-model'), isNull);
      expect(SpeechModel.byId(null), isNull);
    });

    test('tokens are downloaded before the large model files', () {
      // An install interrupted early then leaves the cheap file done and the
      // expensive ones resumable, rather than the other way round.
      expect(SpeechModel.tinyEn.files.first.file, contains('tokens'));
    });
  });
}
