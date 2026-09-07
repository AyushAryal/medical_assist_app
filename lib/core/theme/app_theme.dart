import 'package:flutter/material.dart';

import 'theme_config.dart';

/// The bottom [NavigationBar]'s content height, themed below instead of left
/// at the Material 3 default (80). Shared as a constant because
/// [BuildContext.bottomBarClearance] (core/design/adaptive.dart) needs the
/// same number to work out how much space a screen must leave clear above
/// the bar — keep the two in sync if this changes.
const double kAppNavigationBarHeight = 68;

/// Builds Flutter [ThemeData] purely from [ThemeConfig] tokens.
///
/// The visual language: surfaces separated by soft shadow rather than hairline
/// borders, generous corner radii, pill-shaped chips, and filled input wells.
/// Restrained is not the same as lifeless — colour is used confidently for
/// identity and hierarchy, and reserved entirely for clinical severity where
/// it carries meaning.
abstract final class AppTheme {
  static ThemeData build(ThemeConfig config, Brightness brightness) {
    final p = config.paletteFor(brightness);
    final t = config.typography;
    final m = config.metrics;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: p.primaryContainer,
      onPrimaryContainer: p.onPrimaryContainer,
      secondary: p.secondary,
      onSecondary: p.onSecondary,
      secondaryContainer: p.surfaceMuted,
      onSecondaryContainer: p.onSurface,
      tertiary: p.accent,
      onTertiary: p.onAccent,
      tertiaryContainer: p.accentSubtle,
      onTertiaryContainer: p.accent,
      error: p.critical,
      onError: p.onCritical,
      errorContainer: p.criticalSubtle,
      onErrorContainer: p.critical,
      surface: p.surface,
      onSurface: p.onSurface,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surfaceMuted,
      surfaceContainer: p.surfaceMuted,
      surfaceContainerHigh: p.surfaceSunken,
      surfaceContainerHighest: p.surfaceSunken,
      onSurfaceVariant: p.onSurfaceMuted,
      outline: p.outline,
      outlineVariant: p.outline,
      scrim: p.scrim,
      shadow: p.shadow,
      inverseSurface: p.onSurface,
      onInverseSurface: p.surface,
      inversePrimary: p.primaryContainer,
    );

    final text = _textTheme(t, p);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // Transparent so the ambient wash behind the app shows through and the
      // translucent panels have something to sample.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: p.surface,
      shadowColor: p.shadow,
      fontFamily: t.fontFamily,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,

      // No hairline under the bar; separation comes from scroll elevation, so
      // an unscrolled screen reads as one calm surface.
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: p.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: p.onSurface, size: 22),
      ),

      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: p.shadow.withValues(alpha: m.shadowOpacity * 3),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(m.radiusMd),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: p.outline,
        thickness: m.hairline,
        space: m.hairline,
      ),

      // Fields read as wells sunk into the card rather than boxes drawn on it.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.onSurface.withValues(alpha: 0.045),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: m.spaceLg,
          vertical: m.spaceMd + 2,
        ),
        labelStyle: text.labelLarge?.copyWith(color: p.onSurfaceMuted),
        floatingLabelStyle: text.labelLarge?.copyWith(color: p.primary),
        hintStyle: text.bodyMedium?.copyWith(color: p.onSurfaceMuted),
        helperStyle: text.bodySmall?.copyWith(color: p.onSurfaceMuted),
        errorStyle: text.bodySmall?.copyWith(color: p.critical),
        border: _fieldBorder(m.radiusSm, Colors.transparent, 0),
        enabledBorder: _fieldBorder(m.radiusSm, Colors.transparent, 0),
        focusedBorder: _fieldBorder(m.radiusSm, p.primary, m.focusBorderWidth),
        errorBorder: _fieldBorder(m.radiusSm, p.critical, m.borderWidth),
        focusedErrorBorder: _fieldBorder(
          m.radiusSm,
          p.critical,
          m.focusBorderWidth,
        ),
        disabledBorder: _fieldBorder(m.radiusSm, Colors.transparent, 0),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(0, m.minTapTarget),
          padding: EdgeInsets.symmetric(horizontal: m.spaceXl),
          textStyle: text.labelLarge,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(m.radiusSm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, m.minTapTarget),
          padding: EdgeInsets.symmetric(horizontal: m.spaceLg),
          textStyle: text.labelLarge,
          side: BorderSide(color: p.outline, width: m.borderWidth),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(m.radiusSm),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: Size(0, m.minTapTarget),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(m.radiusSm),
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceMuted,
        selectedColor: p.primaryContainer,
        checkmarkColor: p.onPrimaryContainer,
        side: BorderSide(color: p.outline, width: m.borderWidth),
        labelStyle: text.labelMedium,
        padding: EdgeInsets.symmetric(
          horizontal: m.spaceMd,
          vertical: m.spaceSm,
        ),
        shape: const StadiumBorder(),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: p.onSurfaceMuted,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(color: p.onSurfaceMuted),
        minVerticalPadding: m.spaceMd,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(m.radiusSm),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: m.elevationSheet,
        showDragHandle: true,
        dragHandleColor: p.outlineStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(m.radiusLg)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(m.radiusMd),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.onSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(m.radiusSm),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        // No pill behind the selected icon. The Material indicator is the one
        // element that read as dated on an iOS-first app; a tab bar that
        // marks the current tab with tint and weight alone is what a modern
        // bar looks like on either platform.
        indicatorColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: 0,
        height: kAppNavigationBarHeight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? p.primary
                : p.onSurfaceMuted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 25,
            color: states.contains(WidgetState.selected)
                ? p.primary
                : p.onSurfaceMuted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        // The default 72dp clips longer destination labels such as
        // "Schedule" against the rail edge.
        minWidth: 88,
        labelType: NavigationRailLabelType.all,
        selectedLabelTextStyle: text.labelSmall?.copyWith(
          color: p.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: text.labelSmall?.copyWith(
          color: p.onSurfaceMuted,
        ),
        selectedIconTheme: IconThemeData(color: p.primary),
        unselectedIconTheme: IconThemeData(color: p.onSurfaceMuted),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: p.primaryContainer,
          selectedForegroundColor: p.onPrimaryContainer,
          side: BorderSide(color: p.outline, width: m.borderWidth),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(m.radiusSm),
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(m.radiusMd),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.surfaceSunken,
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(
    double radius,
    Color color,
    double width,
  ) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(ThemeTypography t, ClinicalPalette p) {
    TextStyle s(
      double size,
      FontWeight weight, {
      Color? color,
      double? spacing,
      double? height,
    }) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height ?? t.baseHeight,
      letterSpacing: spacing,
      color: color ?? p.onSurface,
    );

    return TextTheme(
      displaySmall: s(
        t.displaySize,
        FontWeight.w700,
        spacing: -0.8,
        height: 1.1,
      ),
      headlineMedium: s(
        t.titleSize + 8,
        FontWeight.w700,
        spacing: -0.6,
        height: 1.12,
      ),
      headlineSmall: s(t.titleSize + 2, FontWeight.w600, height: 1.25),
      titleLarge: s(t.titleSize, FontWeight.w700, spacing: -0.4),
      titleMedium: s(t.sectionSize, FontWeight.w700, spacing: -0.2),
      titleSmall: s(t.labelSize + 1, FontWeight.w600),
      bodyLarge: s(t.bodySize + 1, FontWeight.w400),
      bodyMedium: s(t.bodySize, FontWeight.w400),
      bodySmall: s(t.labelSize, FontWeight.w400, color: p.onSurfaceMuted),
      labelLarge: s(t.labelSize + 1, FontWeight.w600),
      labelMedium: s(t.labelSize, FontWeight.w500),
      labelSmall: s(
        t.captionSize,
        FontWeight.w600,
        color: p.onSurfaceMuted,
        spacing: 0.3,
      ),
    );
  }
}
