import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/core/db/app_meta_store.dart';
import 'package:medical_app/core/modules/module_registry.dart';
import 'package:medical_app/core/modules/workflow_preferences.dart';

/// An in-memory stand-in for the encrypted meta store.
class _FakeMeta implements MetaKeyValue {
  final Map<String, String?> _values = <String, String?>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async =>
      _values[key] = value;
}

void main() {
  test('triage is a clinic-configurable module', () {
    expect(WorkflowPreferences.configurable, contains(ModuleId.triage));
  });

  test('optional workflows default off when nothing is saved', () async {
    final prefs = WorkflowPreferences(_FakeMeta());
    await prefs.load();
    expect(prefs.isEnabled(ModuleId.triage), isFalse);
  });

  test('enabling persists and restores across a reload', () async {
    final meta = _FakeMeta();

    final prefs = WorkflowPreferences(meta);
    await prefs.load();
    await prefs.setEnabled(ModuleId.triage, true);
    expect(prefs.isEnabled(ModuleId.triage), isTrue);

    // A fresh instance over the same store restores the choice.
    final reloaded = WorkflowPreferences(meta);
    await reloaded.load();
    expect(reloaded.isEnabled(ModuleId.triage), isTrue);
  });

  test('disabling removes it from the saved set', () async {
    final meta = _FakeMeta();
    final prefs = WorkflowPreferences(meta);
    await prefs.load();
    await prefs.setEnabled(ModuleId.triage, true);
    await prefs.setEnabled(ModuleId.triage, false);

    final reloaded = WorkflowPreferences(meta);
    await reloaded.load();
    expect(reloaded.isEnabled(ModuleId.triage), isFalse);
  });

  test('setEnabled notifies listeners only on a real change', () async {
    final prefs = WorkflowPreferences(_FakeMeta());
    await prefs.load();
    var notifications = 0;
    prefs.addListener(() => notifications++);

    await prefs.setEnabled(ModuleId.triage, true); // changes
    await prefs.setEnabled(ModuleId.triage, true); // no-op
    expect(notifications, 1);
  });

  test('refuses to govern a module that is not clinic-configurable', () async {
    final prefs = WorkflowPreferences(_FakeMeta());
    await prefs.load();
    await prefs.setEnabled(ModuleId.patients, true);
    expect(prefs.isEnabled(ModuleId.patients), isFalse);
  });
}
