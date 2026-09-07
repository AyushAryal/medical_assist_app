import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/clinical/flags/clinical_flag.dart';
import 'package:medical_app/clinical/flags/red_flag_rule.dart';

void main() {
  test('empty or absent text yields no flags', () {
    expect(RedFlagRule.fromText('p', null, source: 's'), isEmpty);
    expect(RedFlagRule.fromText('p', '   ', source: 's'), isEmpty);
  });

  test('a red-flag complaint becomes a critical flag with its subject', () {
    final flags = RedFlagRule.fromText('p1', 'chest pain since morning',
        source: 'Presenting complaint');
    expect(flags, hasLength(1));
    final flag = flags.single;
    expect(flag.subjectId, 'p1');
    expect(flag.kind, FlagKind.redFlag);
    expect(flag.severity, FlagSeverity.critical);
    expect(flag.isCritical, isTrue);
    expect(flag.source, 'Presenting complaint');
    expect(flag.reason, contains('chest pain'));
  });

  test('a negated complaint is not flagged', () {
    // NoteIntelligence handles negation; the rule inherits it.
    final flags =
        RedFlagRule.fromText('p', 'denies chest pain', source: 's');
    expect(flags, isEmpty);
  });

  test('ordinary text produces nothing', () {
    final flags = RedFlagRule.fromText('p', 'routine blood pressure check',
        source: 's');
    expect(flags, isEmpty);
  });

  test('the same red flag is not emitted twice', () {
    final flags = RedFlagRule.fromText(
        'p', 'chest pain, worsening chest pain', source: 's');
    expect(flags, hasLength(1));
  });
}
