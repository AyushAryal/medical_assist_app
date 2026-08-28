import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps features liftable and the dependency direction pointing inward.
///
/// The whole point of the module layout is that a feature can be dropped into
/// another project, or swapped out of this one, without unpicking a web of
/// imports. Two rules make that true, and both erode silently the moment they
/// are not enforced:
///
///  1. A feature reaches another feature only through its public barrel
///     (`features/<name>/<name>.dart`), never a deep file. The barrel is the
///     contract; a deep import couples you to an internal that may move.
///  2. The domain and capability layers — `ai/`, `clinical/`, `data/` — never
///     import `features/`. Dependencies point inward: UI depends on the
///     kernel, never the reverse. A pipeline that imports a screen cannot be
///     lifted without the screen.
///
/// The composition roots (`main.dart`, `app.dart`, `core/routing/`) are where
/// features are wired together, so they are allowed to name features — that is
/// their job.
String _resolve(String fromFile, String importPath) {
  final segments = fromFile.split('/')..removeLast();
  for (final part in importPath.split('/')) {
    if (part == '..') {
      segments.removeLast();
    } else if (part != '.') {
      segments.add(part);
    }
  }
  return segments.join('/');
}

Iterable<String> _relativeImports(String source) sync* {
  for (final match in RegExp(r'''import\s+['"]([^'"]+)['"]''').allMatches(source)) {
    final target = match.group(1)!;
    if (target.startsWith('.')) yield target;
  }
}

List<({String path, String source})> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => (path: f.path, source: f.readAsStringSync()))
    .toList();

void main() {
  test('a feature imports another feature only through its barrel', () {
    final violations = <String>[];

    for (final file in _dartFiles('lib/features')) {
      // lib/features/<feature>/...
      final ownFeature = file.path.split('/')[2];
      for (final import in _relativeImports(file.source)) {
        final resolved = _resolve(file.path, import);
        if (!resolved.startsWith('lib/features/')) continue;
        final targetFeature = resolved.split('/')[2];
        if (targetFeature == ownFeature) continue;

        final barrel = 'lib/features/$targetFeature/$targetFeature.dart';
        if (resolved != barrel) {
          violations.add('${file.path}: imports $import '
              '(reach $targetFeature through its barrel '
              "'$targetFeature/$targetFeature.dart' instead)");
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Features must talk to each other only through public barrels, '
          'so a feature stays liftable.\n${violations.join('\n')}',
    );
  });

  test('domain and capability layers never import features', () {
    final violations = <String>[];

    for (final layer in <String>['lib/ai', 'lib/clinical', 'lib/data']) {
      for (final file in _dartFiles(layer)) {
        for (final import in _relativeImports(file.source)) {
          final resolved = _resolve(file.path, import);
          if (resolved.startsWith('lib/features/')) {
            violations.add('${file.path}: imports $import');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'ai/, clinical/ and data/ are the reusable inner layers; they '
          'must not depend on UI. Move the shared piece down, or invert the '
          'dependency.\n${violations.join('\n')}',
    );
  });
}
