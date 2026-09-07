import 'package:flutter/foundation.dart';

import '../db/app_meta_store.dart';
import 'module_registry.dart';

/// Which optional workflow modules *this clinic* has turned on.
///
/// Separate from [Entitlements] on purpose. Entitlements is what the licence
/// *allows*; this is what the clinic *chose*. A rural single-hander and a busy
/// urban clinic can hold the same licence and want different workflows — not
/// every clinic triages — so a module marked [ModuleDescriptor.clinicConfigurable]
/// only appears when it is both licensed and switched on here.
///
/// These default **off**: an optional workflow a clinic never asked for should
/// not clutter their app until they opt in. The choice persists inside the
/// encrypted database (via [AppMetaStore]), not a plist, because which
/// workflows a clinic runs is operational context for a medical record.
class WorkflowPreferences extends ChangeNotifier {
  WorkflowPreferences(this._meta);

  final MetaKeyValue _meta;

  /// Key in `app_meta`. Holds a comma-separated list of enabled module names.
  static const String metaKey = 'enabled_workflows';

  Set<ModuleId> _enabled = <ModuleId>{};

  /// The modules a clinic may toggle — every descriptor that opted in.
  static List<ModuleId> get configurable => ModuleRegistry.all.values
      .where((d) => d.clinicConfigurable)
      .map((d) => d.id)
      .toList(growable: false);

  bool isEnabled(ModuleId id) => _enabled.contains(id);

  /// Restores the saved choice. Absent key → nothing enabled → every optional
  /// workflow stays off, which is the intended default.
  Future<void> load() async {
    final raw = await _meta.read(metaKey);
    _enabled = _parse(raw);
    notifyListeners();
  }

  Future<void> setEnabled(ModuleId id, bool enabled) async {
    // Only govern modules that actually opted into clinic configuration; a
    // stray id must never silently gate a core feature.
    if (!configurable.contains(id)) return;
    if (isEnabled(id) == enabled) return;

    final next = <ModuleId>{..._enabled};
    if (enabled) {
      next.add(id);
    } else {
      next.remove(id);
    }
    _enabled = next;
    await _meta.write(metaKey, _encode(next));
    notifyListeners();
  }

  static Set<ModuleId> _parse(String? raw) {
    if (raw == null || raw.isEmpty) return <ModuleId>{};
    final byName = <String, ModuleId>{
      for (final id in configurable) id.name: id,
    };
    return <ModuleId>{
      for (final token in raw.split(',')) ?byName[token.trim()],
    };
  }

  static String _encode(Set<ModuleId> ids) =>
      ids.map((id) => id.name).join(',');
}
