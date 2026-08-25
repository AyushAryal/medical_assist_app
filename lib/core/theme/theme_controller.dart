import 'package:flutter/material.dart';

import 'theme_config.dart';

/// Holds the loaded [ThemeConfig] and the user's light/dark preference.
///
/// The config is loaded once at startup; [reload] exists so a future
/// "practice branding" feature can swap the token file at runtime without a
/// restart.
class ThemeController extends ChangeNotifier {
  ThemeController(this._config);

  ThemeConfig _config;
  ThemeMode _mode = ThemeMode.system;
  String _assetPath = ThemeConfig.defaultAsset;

  ThemeConfig get config => _config;
  ThemeMode get mode => _mode;
  String get assetPath => _assetPath;

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  Future<void> reload(String assetPath) async {
    _config = await ThemeConfig.load(assetPath);
    _assetPath = assetPath;
    notifyListeners();
  }
}
