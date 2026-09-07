import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The clinical kernel is the source of truth, so it must stay a pure,
/// portable core: plain Dart logic with no UI and no model behind it.
///
/// This is rule 1 of the no-ambiguity contract (see `ClinicalWorkflows.md`).
/// The engines here decide who is seen first and what a record says; if any of
/// that logic could reach into Flutter or a language model, its output would
/// stop being reproducible from its inputs alone — which is the whole point of
/// keeping it here. It also keeps `clinical/` liftable into another project.
void main() {
  test('lib/clinical imports no Flutter, no dart:ui, and no model/AI layer',
      () {
    final banned = <RegExp>[
      RegExp(r'''import\s+['"]package:flutter/'''),
      RegExp(r'''import\s+['"]dart:ui'''),
      RegExp(r'''import\s+['"].*\bai/'''), // the model pipeline
    ];

    final violations = <String>[];
    for (final file in Directory('lib/clinical')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final pattern in banned) {
        if (pattern.hasMatch(source)) {
          violations.add('${file.path}: ${pattern.pattern}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'The clinical kernel must stay pure and deterministic.\n'
          '${violations.join('\n')}',
    );
  });
}
