// Dark trading theme.
//
// The palette is intentionally defined as plain ARGB constants (instead of
// `Color.withOpacity`) so the code compiles unchanged across Flutter versions
// and every translucent surface is explicit and reviewable.

import 'package:flutter/material.dart';

/// Central colour palette used across the app.
abstract final class AppColors {
  /// App background (slightly blue-black, easy on the eyes at night).
  static const Color background = Color(0xFF0B0E11);

  /// Cards, sheets and form surfaces.
  static const Color surface = Color(0xFF161A1E);

  /// Elevated / secondary surfaces (input fields, chips).
  static const Color surfaceAlt = Color(0xFF1E2329);

  /// Dividers and 1px borders.
  static const Color border = Color(0xFF2B3139);

  /// Binance yellow, the primary accent.
  static const Color primary = Color(0xFFF0B90B);

  /// Accent used for buy / positive movement.
  static const Color green = Color(0xFF0ECB81);

  /// Accent used for sell / negative movement.
  static const Color red = Color(0xFFF6465D);

  /// Informational accent.
  static const Color blue = Color(0xFF2962FF);

  /// Warning accent (testnet badges, disclaimers).
  static const Color amber = Color(0xFFF0B90B);

  static const Color textPrimary = Color(0xFFEAECEF);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);

  // Pre-computed translucent overlays (avoid withOpacity/withValues so the code
  // is version agnostic).
  static const Color greenSoft = Color(0x260ECB81);
  static const Color redSoft = Color(0x26F6465D);
  static const Color primarySoft = Color(0x26F0B90B);
  static const Color blueSoft = Color(0x262962FF);
  static const Color greySoft = Color(0x2A9CA3AF);
  static const Color surfaceSoft = Color(0x99FFFFFF);
  static const Color scrim = Color(0xCC000000);
}

/// `ThemeData` for the whole app.
abstract final class AppTheme {
  static ThemeData get dark {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: AppColors.background,
      secondary: AppColors.green,
      onSecondary: AppColors.background,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.red,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.border,
      splashColor: AppColors.primarySoft,
      highlightColor: AppColors.primarySoft,
      // Typography colours are derived from the scheme; individual screens use
      // `AppTextStyles` for trading specific styles.
      visualDensity: VisualDensity.standard,
    );
  }
}

/// Text styles used by the trading widgets.
///
/// `tabularFigures` keeps digits monospaced so live prices do not jitter while
/// they tick.
abstract final class AppTextStyles {
  static const TextStyle display = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.8,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontSize: 13,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.textMuted,
  );

  static const TextStyle mono = TextStyle(
    fontSize: 14,
    color: AppColors.textPrimary,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle monoSmall = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );
}
