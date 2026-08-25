import 'package:flutter/material.dart';

import 'theme_config.dart';

/// Exposes the raw design tokens below the [MaterialApp] so widgets can reach
/// semantic clinical colours that [ColorScheme] has no slot for (normal /
/// caution / critical / allergy banner).
class ThemeScope extends InheritedWidget {
  const ThemeScope({
    super.key,
    required this.config,
    required this.brightness,
    required super.child,
  });

  final ThemeConfig config;
  final Brightness brightness;

  static ThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope is missing above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(ThemeScope oldWidget) =>
      oldWidget.config != config || oldWidget.brightness != brightness;
}

extension ThemeScopeX on BuildContext {
  /// Semantic clinical colours for the active brightness.
  ClinicalPalette get palette =>
      ThemeScope.of(this).config.paletteFor(Theme.of(this).brightness);

  /// Spacing, radii and breakpoint tokens.
  ThemeMetrics get metrics => ThemeScope.of(this).config.metrics;

  ThemeTypography get typography => ThemeScope.of(this).config.typography;

  TextTheme get texts => Theme.of(this).textTheme;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Opacity for a translucent content panel, matched to brightness — a dark
  /// material needs to be more opaque to keep text legible.
  double get glassOpacity => isDark
      ? metrics.glassOpacityDark
      : metrics.glassOpacityLight;

  double get chromeOpacity => isDark
      ? metrics.chromeOpacityDark
      : metrics.chromeOpacityLight;

  /// Alpha for a coloured icon's backing tint, matched to the active
  /// brightness — the same value looks bold on white and invisible on black.
  double get iconTintAlpha => Theme.of(this).brightness == Brightness.dark
      ? metrics.iconTintAlphaDark
      : metrics.iconTintAlphaLight;

  bool get isTablet =>
      MediaQuery.sizeOf(this).width >= ThemeScope.of(this).config.metrics.tabletBreakpoint;

  bool get isWide =>
      MediaQuery.sizeOf(this).width >= ThemeScope.of(this).config.metrics.wideBreakpoint;
}
