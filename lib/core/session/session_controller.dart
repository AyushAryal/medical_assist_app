import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../../data/models/clinic.dart';
import '../../data/repositories/clinical_repository.dart';
import '../db/app_meta_store.dart';
import '../utils/ids.dart';

/// Working context for the current shift: which clinic the user is at and who
/// is signing.
///
/// Clinic selection is sticky across launches. A clinician who works Tuesdays
/// at one site should not have to re-pick it every time they open the app —
/// but they must be able to see and change it from every screen, because
/// recording an encounter against the wrong site corrupts the record.
class SessionController extends ChangeNotifier {
  SessionController(this._repository, this._meta);

  final ClinicalRepository _repository;
  final AppMetaStore _meta;

  List<Clinic> _clinics = const <Clinic>[];
  Clinic? _activeClinic;
  String _providerName = '';
  String _deviceId = '';
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLoading = true;

  List<Clinic> get clinics => _clinics;
  Clinic? get activeClinic => _activeClinic;
  String get providerName => _providerName;
  String get deviceId => _deviceId;
  ThemeMode get themeMode => _themeMode;
  bool get isLoading => _isLoading;
  bool get isReady => _activeClinic != null;

  /// Falls back to the device id when no clinician name is set, so a signature
  /// is never blank — an unattributed signature is worse than an ugly one.
  String get signatureName =>
      _providerName.trim().isEmpty ? 'Device $_deviceId' : _providerName.trim();

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _deviceId = await _meta.read(AppMetaStore.keyDeviceId) ??
        await _createDeviceId();
    _providerName = await _meta.read(AppMetaStore.keyProviderName) ?? '';
    _themeMode = _parseThemeMode(await _meta.read(AppMetaStore.keyThemeMode));

    await _repository.ensureDefaultClinic();
    _clinics = await _repository.clinics.all();

    final storedId = await _meta.read(AppMetaStore.keyActiveClinic);
    _activeClinic = _clinics.where((c) => c.id == storedId).firstOrNull ??
        (_clinics.isEmpty ? null : _clinics.first);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshClinics() async {
    _clinics = await _repository.clinics.all();
    if (_activeClinic != null &&
        !_clinics.any((c) => c.id == _activeClinic!.id)) {
      _activeClinic = _clinics.isEmpty ? null : _clinics.first;
      await _meta.write(AppMetaStore.keyActiveClinic, _activeClinic?.id);
    }
    notifyListeners();
  }

  Future<void> setActiveClinic(Clinic clinic) async {
    _activeClinic = clinic;
    await _meta.write(AppMetaStore.keyActiveClinic, clinic.id);
    notifyListeners();
  }

  Future<void> setProviderName(String name) async {
    _providerName = name;
    await _meta.write(AppMetaStore.keyProviderName, name);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _meta.write(AppMetaStore.keyThemeMode, mode.name);
    notifyListeners();
  }

  Future<String> _createDeviceId() async {
    final id = newId().substring(0, 8).toUpperCase();
    await _meta.write(AppMetaStore.keyDeviceId, id);
    return id;
  }

  static ThemeMode _parseThemeMode(String? value) =>
      ThemeMode.values.where((m) => m.name == value).firstOrNull ??
      ThemeMode.system;
}
