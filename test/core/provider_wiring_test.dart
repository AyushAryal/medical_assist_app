import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against a mistake that only shows up at runtime, on a device, after
/// unlock — which is the worst possible place to find it.
///
/// `Provider<T>` throws if `T` is a `Listenable`, because it cannot propagate
/// change notifications; such a type needs `ChangeNotifierProvider<T>`. The
/// analyzer does not catch it and neither do the pure-logic tests, so this
/// walks the source instead.
void main() {
  late final List<File> sources;

  setUpAll(() {
    sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  });

  test('no ChangeNotifier is exposed through a plain Provider', () {
    final contents = <String, String>{
      for (final file in sources) file.path: file.readAsStringSync(),
    };

    // Every ChangeNotifier subclass declared in this codebase.
    final notifier = RegExp(
      r'class\s+(\w+)\s+extends\s+ChangeNotifier\b',
      multiLine: true,
    );
    final notifiers = <String>{
      for (final source in contents.values)
        ...notifier.allMatches(source).map((m) => m.group(1)!),
    };

    expect(
      notifiers,
      isNotEmpty,
      reason: 'Expected to find ChangeNotifier subclasses; the scan is broken.',
    );

    final offences = <String>[];
    for (final name in notifiers) {
      // Lookbehind keeps `ChangeNotifierProvider<Foo>` and
      // `ListenableProvider<Foo>` from matching.
      final misuse = RegExp('(?<![A-Za-z_])Provider<$name>');
      contents.forEach((path, source) {
        for (final line in const LineSplitter().convert(source)) {
          if (misuse.hasMatch(line)) {
            offences.add('$path: ${line.trim()}');
          }
        }
      });
    }

    expect(
      offences,
      isEmpty,
      reason: 'These ChangeNotifiers are provided with a plain Provider, which '
          'throws at runtime. Use ChangeNotifierProvider instead:\n'
          '${offences.join('\n')}',
    );
  });

  test('AppBootstrap is provided exactly once, as a ChangeNotifierProvider', () {
    final declarations = <String>[];
    for (final file in sources) {
      for (final line in const LineSplitter().convert(file.readAsStringSync())) {
        if (RegExp(r'Provider<AppBootstrap>').hasMatch(line)) {
          declarations.add('${file.path}: ${line.trim()}');
        }
      }
    }

    // Exactly one declaration, in main.dart, and it must be a
    // ChangeNotifierProvider. Re-providing it lower in the tree is what caused
    // the original runtime failure.
    expect(declarations, hasLength(1), reason: declarations.join('\n'));
    expect(declarations.single, contains('main.dart'));
    expect(declarations.single, contains('ChangeNotifierProvider'));
  });
}

/// `LineSplitter` without pulling `dart:convert` into the test's namespace
/// alongside `dart:io`.
class LineSplitter {
  const LineSplitter();
  List<String> convert(String input) => input.split('\n');
}
