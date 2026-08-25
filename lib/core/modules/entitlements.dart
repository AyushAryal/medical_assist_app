import 'package:flutter/foundation.dart';

import 'module_registry.dart';

/// The subscription state the rest of the app reads from.
///
/// TODO(round 2): back this with a signed, offline-verifiable licence.
/// The intended shape is an Ed25519-signed token carrying the granted module
/// set, a not-after timestamp and a device binding, cached in the keystore and
/// re-validated on every launch. Until that exists this returns a locally
/// configured set, and nothing here should be treated as a security boundary —
/// see `SystemArchitecture.md` § Subscription enforcement for why gating alone
/// cannot protect data, and what will.
class Entitlements extends ChangeNotifier {
  Entitlements({Set<ModuleId>? granted, this.plan = ModuleTier.core})
      : _granted = ModuleRegistry.resolve(
          granted ?? ModuleRegistry.all.keys.toSet(),
        );

  Set<ModuleId> _granted;
  final ModuleTier plan;
  DateTime? _validUntil;

  Set<ModuleId> get granted => Set.unmodifiable(_granted);
  DateTime? get validUntil => _validUntil;

  bool get isExpired =>
      _validUntil != null && DateTime.now().isAfter(_validUntil!);

  bool has(ModuleId id) => !isExpired && _granted.contains(id);

  bool hasAll(Iterable<ModuleId> ids) => ids.every(has);

  bool hasAny(Iterable<ModuleId> ids) => ids.any(has);

  List<ModuleDescriptor> get lockedModules => ModuleRegistry.all.values
      .where((d) => !has(d.id))
      .toList(growable: false);

  /// Development affordance for exercising the locked-state UI without a
  /// licence server.
  void applyGrant(Set<ModuleId> granted, {DateTime? validUntil}) {
    _granted = ModuleRegistry.resolve(granted);
    _validUntil = validUntil;
    notifyListeners();
  }
}
