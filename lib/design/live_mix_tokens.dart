import 'package:flutter/material.dart';

/// Executable Flutter mapping of the repository-owned design contract.
///
/// Canonical values live in `design/tokens.json`. Changes here must be kept
/// byte-for-byte equivalent to that semantic contract and are protected by
/// `test/design_contract_test.dart`.
abstract final class LiveMixTokens {
  static const Color surfaceBase = Color(0xFF111315);
  static const Color surfaceRack = Color(0xFF1C1F23);
  static const Color surfaceStrip = Color(0xFF24292F);

  static const Color accentOchre = Color(0xFFD96528);
  static const Color accentCopper = Color(0xFF2A7A6D);
  static const Color statusWarn = Color(0xFFD48822);

  static const Color meterNominal = Color(0xFF22C55E);
  static const Color meterHeadroom = Color(0xFFEAB308);
  static const Color meterClip = Color(0xFFEF4444);
  static const Color meterInactive = Color(0xFF1A1D20);

  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);

  static const List<num> meterScaleDbfs = <num>[0, -6, -12, -18, -24, -36, -60];
  static const List<num> spacing = <num>[4, 8, 12, 16, 24, 32];
  static const List<num> radii = <num>[2, 4, 8];

  static const double focusWidth = 2;
  static const double minimumTarget = 44;
  static const double disabledOpacity = 0.4;

  /// Copper alone does not meet the 3:1 non-text contrast target on strip.
  static const Color focusFallbackOnStrip = textPrimary;
}

abstract final class LiveMixTextStyles {
  static const TextStyle sectionDisplay = TextStyle(
    color: LiveMixTokens.textPrimary,
    fontFamily: 'Roboto Condensed',
    fontWeight: FontWeight.w700,
    fontSize: 24,
    height: 1.0,
    letterSpacing: 0.96,
  );

  static const TextStyle uiLabel = TextStyle(
    color: LiveMixTokens.textPrimary,
    fontFamily: 'Roboto Condensed',
    fontWeight: FontWeight.w600,
    fontSize: 12,
    height: 1.15,
    letterSpacing: 0.72,
  );

  static const TextStyle body = TextStyle(
    color: LiveMixTokens.textPrimary,
    fontFamily: 'Inter',
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 1.4,
  );

  static const TextStyle numericTelemetry = TextStyle(
    color: LiveMixTokens.textPrimary,
    fontFamily: 'Roboto Mono',
    fontWeight: FontWeight.w600,
    fontSize: 16,
    height: 1.2,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}

abstract final class LiveMixTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: LiveMixTokens.accentOchre,
      secondary: LiveMixTokens.accentCopper,
      surface: LiveMixTokens.surfaceRack,
      error: LiveMixTokens.meterClip,
      onPrimary: LiveMixTokens.textPrimary,
      onSecondary: LiveMixTokens.textPrimary,
      onSurface: LiveMixTokens.textPrimary,
      onError: LiveMixTokens.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: LiveMixTokens.surfaceBase,
      focusColor: LiveMixTokens.accentCopper,
      disabledColor: LiveMixTokens.textSecondary.withValues(alpha: LiveMixTokens.disabledOpacity),
      textTheme: const TextTheme(
        titleLarge: LiveMixTextStyles.sectionDisplay,
        labelLarge: LiveMixTextStyles.uiLabel,
        bodyMedium: LiveMixTextStyles.body,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: LiveMixTokens.surfaceStrip,
        labelStyle: LiveMixTextStyles.uiLabel,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: LiveMixTokens.textSecondary),
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: LiveMixTokens.accentCopper, width: LiveMixTokens.focusWidth),
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
    );
  }
}
