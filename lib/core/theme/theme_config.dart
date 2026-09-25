import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Colour + metric tokens deserialised from `assets/theme/*.json`.
///
/// Widget code must never hardcode a colour or a spacing literal. It reads
/// tokens from here via `context.tokens` / `context.palette` so the whole app
/// can be re-skinned by editing one JSON file.
class ThemeConfig {
  const ThemeConfig({
    required this.id,
    required this.name,
    required this.typography,
    required this.metrics,
    required this.light,
    required this.dark,
  });

  final String id;
  final String name;
  final ThemeTypography typography;
  final ThemeMetrics metrics;
  final ClinicalPalette light;
  final ClinicalPalette dark;

  static const String defaultAsset = 'assets/theme/clinical.json';

  static Future<ThemeConfig> load([String assetPath = defaultAsset]) async {
    final raw = await rootBundle.loadString(assetPath);
    return ThemeConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  factory ThemeConfig.fromJson(Map<String, dynamic> json) {
    return ThemeConfig(
      id: json['id'] as String? ?? 'clinical',
      name: json['name'] as String? ?? 'Clinical',
      typography: ThemeTypography.fromJson(
        json['typography'] as Map<String, dynamic>? ?? const {},
      ),
      metrics: ThemeMetrics.fromJson(
        json['metrics'] as Map<String, dynamic>? ?? const {},
      ),
      light: ClinicalPalette.fromJson(json['light'] as Map<String, dynamic>),
      dark: ClinicalPalette.fromJson(json['dark'] as Map<String, dynamic>),
    );
  }

  ClinicalPalette paletteFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

class ThemeTypography {
  const ThemeTypography({
    this.fontFamily,
    this.displaySize = 28,
    this.titleSize = 20,
    this.sectionSize = 16,
    this.bodySize = 15,
    this.labelSize = 13,
    this.captionSize = 11.5,
    this.dataSize = 17,
    this.baseHeight = 1.35,
  });

  /// Null keeps the platform default face, which is the safest choice for
  /// clinical legibility across the OEM devices this ships to.
  final String? fontFamily;
  final double displaySize;
  final double titleSize;
  final double sectionSize;
  final double bodySize;
  final double labelSize;
  final double captionSize;

  /// Size for numeric clinical readings (vitals, doses) — deliberately larger
  /// than body text so values stay readable at arm's length.
  final double dataSize;
  final double baseHeight;

  factory ThemeTypography.fromJson(Map<String, dynamic> json) {
    double d(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    return ThemeTypography(
      fontFamily: json['fontFamily'] as String?,
      displaySize: d('displaySize', 28),
      titleSize: d('titleSize', 20),
      sectionSize: d('sectionSize', 16),
      bodySize: d('bodySize', 15),
      labelSize: d('labelSize', 13),
      captionSize: d('captionSize', 11.5),
      dataSize: d('dataSize', 17),
      baseHeight: d('baseHeight', 1.35),
    );
  }
}

class ThemeMetrics {
  const ThemeMetrics({
    this.spaceXs = 4,
    this.spaceSm = 8,
    this.spaceMd = 12,
    this.spaceLg = 16,
    this.spaceXl = 24,
    this.space2xl = 32,
    this.radiusXs = 4,
    this.radiusSm = 6,
    this.radiusMd = 10,
    this.radiusLg = 14,
    this.borderWidth = 1,
    this.focusBorderWidth = 2,
    this.minTapTarget = 48,
    this.fieldHeight = 52,
    this.tabletBreakpoint = 720,
    this.wideBreakpoint = 1080,
    this.contentMaxWidth = 760,
    this.elevationCard = 0,
    this.elevationSheet = 3,
    this.glassBlur = 28,
    this.glassOpacityLight = 0.74,
    this.glassOpacityDark = 0.58,
    this.chromeBlur = 32,
    this.chromeOpacityLight = 0.80,
    this.chromeOpacityDark = 0.66,
    this.hairline = 0.5,
    this.iconTintAlphaLight = 0.12,
    this.iconTintAlphaDark = 0.22,
    this.shadowOpacity = 0.055,
    this.shadowBlur = 18,
    this.shadowOffsetY = 4,
  });

  final double spaceXs;
  final double spaceSm;
  final double spaceMd;
  final double spaceLg;
  final double spaceXl;
  final double space2xl;
  /// For details too small for the standard scale — progress tracks, accent
  /// strips, tiny badges.
  final double radiusXs;
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double borderWidth;
  final double focusBorderWidth;
  final double minTapTarget;
  final double fieldHeight;
  final double tabletBreakpoint;
  final double wideBreakpoint;
  final double contentMaxWidth;
  final double elevationCard;
  final double elevationSheet;

  /// Translucency. Blur is what turns a panel into a *material*: the layer
  /// beneath stays faintly visible through it, which is what gives the
  /// interface depth without resorting to gradients or heavy shadows.
  final double glassBlur;
  final double glassOpacityLight;
  final double glassOpacityDark;

  /// Chrome (app bars, nav bars) sits closer to opaque than content panels do,
  /// so text over it stays legible while scrolling content passes beneath.
  final double chromeBlur;
  final double chromeOpacityLight;
  final double chromeOpacityDark;

  /// Sub-pixel separator width. A full logical pixel reads as a heavy rule on
  /// a modern high-density display.
  final double hairline;

  /// How strongly a coloured icon's backing tint reads. A dark ground needs
  /// far more alpha than a light one for the same perceived presence, so the
  /// two are separate tokens rather than one shared value.
  final double iconTintAlphaLight;
  final double iconTintAlphaDark;

  /// Cards are separated by a soft shadow rather than a hard border. Material
  /// elevation is left at 0 and the shadow drawn explicitly, so its weight is
  /// a design token rather than a Material constant.
  final double shadowOpacity;
  final double shadowBlur;
  final double shadowOffsetY;

  factory ThemeMetrics.fromJson(Map<String, dynamic> json) {
    double d(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    return ThemeMetrics(
      spaceXs: d('spaceXs', 4),
      spaceSm: d('spaceSm', 8),
      spaceMd: d('spaceMd', 12),
      spaceLg: d('spaceLg', 16),
      spaceXl: d('spaceXl', 24),
      space2xl: d('space2xl', 32),
      radiusXs: d('radiusXs', 4),
      radiusSm: d('radiusSm', 6),
      radiusMd: d('radiusMd', 10),
      radiusLg: d('radiusLg', 14),
      borderWidth: d('borderWidth', 1),
      focusBorderWidth: d('focusBorderWidth', 2),
      minTapTarget: d('minTapTarget', 48),
      fieldHeight: d('fieldHeight', 52),
      tabletBreakpoint: d('tabletBreakpoint', 720),
      wideBreakpoint: d('wideBreakpoint', 1080),
      contentMaxWidth: d('contentMaxWidth', 760),
      elevationCard: d('elevationCard', 0),
      elevationSheet: d('elevationSheet', 3),
      glassBlur: d('glassBlur', 28),
      glassOpacityLight: d('glassOpacityLight', 0.74),
      glassOpacityDark: d('glassOpacityDark', 0.58),
      chromeBlur: d('chromeBlur', 32),
      chromeOpacityLight: d('chromeOpacityLight', 0.80),
      chromeOpacityDark: d('chromeOpacityDark', 0.66),
      hairline: d('hairline', 0.5),
      iconTintAlphaLight: d('iconTintAlphaLight', 0.12),
      iconTintAlphaDark: d('iconTintAlphaDark', 0.22),
      shadowOpacity: d('shadowOpacity', 0.055),
      shadowBlur: d('shadowBlur', 18),
      shadowOffsetY: d('shadowOffsetY', 4),
    );
  }
}

/// Clinical semantic colours. `normal` / `caution` / `critical` map onto the
/// severity of an observation, not onto a generic UI state — keeping that
/// mapping in one place is what stops a "red because it's a delete button" and
/// a "red because the patient is unstable" from ever looking the same.
class ClinicalPalette {
  const ClinicalPalette({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.surface,
    required this.onSurface,
    required this.surfaceMuted,
    required this.surfaceSunken,
    required this.onSurfaceMuted,
    required this.outline,
    required this.outlineStrong,
    required this.scrim,
    required this.shadow,
    required this.heroSurface,
    required this.onHeroSurface,
    required this.glassTint,
    required this.ambientOne,
    required this.ambientTwo,
    required this.accent,
    required this.onAccent,
    required this.accentSubtle,
    required this.avatarTones,
    required this.normal,
    required this.onNormal,
    required this.normalSubtle,
    required this.caution,
    required this.onCaution,
    required this.cautionSubtle,
    required this.critical,
    required this.onCritical,
    required this.criticalSubtle,
    required this.info,
    required this.onInfo,
    required this.infoSubtle,
    required this.allergyBanner,
    required this.onAllergyBanner,
    required this.signedLock,
    required this.draftAccent,
  });

  final Brightness brightness;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color surface;
  final Color onSurface;
  final Color surfaceMuted;
  final Color surfaceSunken;
  final Color onSurfaceMuted;
  final Color outline;
  final Color outlineStrong;
  final Color scrim;
  final Color shadow;

  /// Fill for large primary surfaces. A vivid accent that reads well on a
  /// small icon becomes glare across a full-width panel, so this is a separate,
  /// deeper tone rather than `primary` reused at scale.
  final Color heroSurface;
  final Color onHeroSurface;

  /// Base colour a translucent panel is tinted with before blurring.
  final Color glassTint;

  /// Two widely-spaced hues washed faintly across the app background. Without
  /// something behind them, translucent panels have nothing to reveal and
  /// collapse back into flat rectangles.
  final Color ambientOne;
  final Color ambientTwo;

  /// A non-semantic highlight. Deliberately distinct from the clinical
  /// severity colours so that "this is a link / a scheduled item" can never be
  /// mistaken for "this patient is unwell".
  final Color accent;
  final Color onAccent;
  final Color accentSubtle;

  /// Muted tones used to colour patient avatars. Giving each chart a stable
  /// colour makes a list of names scannable without adding any clinical
  /// meaning to the colour.
  final List<Color> avatarTones;

  final Color normal;
  final Color onNormal;
  final Color normalSubtle;
  final Color caution;
  final Color onCaution;
  final Color cautionSubtle;
  final Color critical;
  final Color onCritical;
  final Color criticalSubtle;
  final Color info;
  final Color onInfo;
  final Color infoSubtle;

  final Color allergyBanner;
  final Color onAllergyBanner;
  final Color signedLock;
  final Color draftAccent;

  factory ClinicalPalette.fromJson(Map<String, dynamic> json) {
    Color c(String key, [String fallback = '#FF00FF']) =>
        _parseHexColor(json[key] as String? ?? fallback);
    return ClinicalPalette(
      brightness: (json['brightness'] as String? ?? 'light') == 'dark'
          ? Brightness.dark
          : Brightness.light,
      primary: c('primary'),
      onPrimary: c('onPrimary'),
      primaryContainer: c('primaryContainer'),
      onPrimaryContainer: c('onPrimaryContainer'),
      secondary: c('secondary'),
      onSecondary: c('onSecondary'),
      surface: c('surface'),
      onSurface: c('onSurface'),
      surfaceMuted: c('surfaceMuted'),
      surfaceSunken: c('surfaceSunken'),
      onSurfaceMuted: c('onSurfaceMuted'),
      outline: c('outline'),
      outlineStrong: c('outlineStrong'),
      scrim: c('scrim'),
      shadow: c('shadow', '#000000'),
      heroSurface: c('heroSurface', '#0A7E8C'),
      onHeroSurface: c('onHeroSurface', '#FFFFFF'),
      glassTint: c('glassTint', '#FFFFFF'),
      ambientOne: c('ambientOne', '#0A7E8C'),
      ambientTwo: c('ambientTwo', '#4B5BD6'),
      accent: c('accent'),
      onAccent: c('onAccent'),
      accentSubtle: c('accentSubtle'),
      avatarTones: ((json['avatarTones'] as List<dynamic>?) ?? const <dynamic>[])
          .map((v) => _parseHexColor(v as String))
          .toList(growable: false),
      normal: c('normal'),
      onNormal: c('onNormal'),
      normalSubtle: c('normalSubtle'),
      caution: c('caution'),
      onCaution: c('onCaution'),
      cautionSubtle: c('cautionSubtle'),
      critical: c('critical'),
      onCritical: c('onCritical'),
      criticalSubtle: c('criticalSubtle'),
      info: c('info'),
      onInfo: c('onInfo'),
      infoSubtle: c('infoSubtle'),
      allergyBanner: c('allergyBanner'),
      onAllergyBanner: c('onAllergyBanner'),
      signedLock: c('signedLock'),
      draftAccent: c('draftAccent'),
    );
  }
}

extension ClinicalPaletteX on ClinicalPalette {
  /// The family warm→cool sweep for brand / hero surfaces: coral → violet →
  /// blue, top-left to bottom-right. Derived from the palette's own tokens —
  /// [ambientOne] (coral), [heroSurface] (violet) and [ambientTwo] (blue) — so
  /// it re-skins with the theme file rather than being a literal, and so a
  /// feature can consume it as an approved token instead of writing a raw
  /// gradient (which the design guardrails forbid).
  ///
  /// Reserved for brand moments — the "next up" hero, the splash. Clinical
  /// content surfaces stay flat and calm.
  LinearGradient get heroGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[ambientOne, heroSurface, ambientTwo],
        stops: const <double>[0.0, 0.55, 1.0],
      );

  /// Stable per-identifier avatar colour. Hashing the id rather than the name
  /// keeps the colour fixed when a patient is renamed.
  Color avatarToneFor(String seed) {
    if (avatarTones.isEmpty) return primaryContainer;
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return avatarTones[hash % avatarTones.length];
  }
}

Color _parseHexColor(String hex) {
  var value = hex.replaceFirst('#', '').trim();
  if (value.length == 6) value = 'FF$value';
  return Color(int.parse(value, radix: 16));
}
