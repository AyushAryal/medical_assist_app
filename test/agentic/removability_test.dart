import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Proves the agentic module is genuinely removable.
///
/// The whole point of `lib/agentic/` is that it can be deleted and the app
/// still builds and runs — every AgentSlot just renders nothing. That only
/// holds if the dependency is one-way: the module may depend on the app, but
/// no app code may depend on the module. The single sanctioned exception is
/// `lib/main.dart`, the composition root, which installs the module in one
/// line. If this test fails, someone reached into `lib/agentic/` from app code
/// and the module is no longer removable.
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

void main() {
  test('only main.dart may depend on lib/agentic/', () {
    final offenders = <String>[];

    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in files) {
      // The module may import its own parts.
      if (file.path.startsWith('lib/agentic/')) continue;
      // The composition root is the one allowed wiring point.
      if (file.path == 'lib/main.dart') continue;

      final source = file.readAsStringSync();
      for (final match
          in RegExp(r'''import\s+['"]([^'"]+)['"]''').allMatches(source)) {
        final import = match.group(1)!;
        String? target;
        if (import.startsWith('package:medical_app/')) {
          target = 'lib/${import.substring('package:medical_app/'.length)}';
        } else if (import.startsWith('.')) {
          target = _resolve(file.path, import);
        }
        if (target != null && target.startsWith('lib/agentic/')) {
          offenders.add('${file.path} -> $import');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'App code must not import the agentic module — it has to stay '
          'deletable. Only lib/main.dart may reference it.\n'
          '${offenders.join('\n')}',
    );
  });
}
