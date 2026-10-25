import 'package:flutter/material.dart';

/// Tokens. DESIGN.md is the contract; this file is its only implementation.
/// Look: white surfaces, pale teal tints for grouping, pill buttons and
/// chips, generous corners, soft teal shadows for depth on buttons and
/// tiles (案 A ホワイト＆ティール, 2026-10-25).

/// Depth for hand-built tiles (件数、行): one soft teal shadow.
List<BoxShadow> appShadow(ColorScheme scheme) => [
      BoxShadow(
        color: scheme.primary.withValues(alpha: scheme.brightness == Brightness.light ? 0.18 : 0.45),
        blurRadius: 14,
        offset: const Offset(0, 5),
      ),
    ];
abstract final class AppRadius {
  static const small = 10.0;
  static const medium = 16.0;
  static const large = 20.0;
}

abstract final class AppSpace {
  static const unit = 8.0;
  static const gutter = 16.0;
}

abstract final class AppSize {
  /// Inline icon inside a text field or a progress row.
  static const iconSmall = 18.0;

  /// Card thumbnail height in the review header.
  static const thumb = 96.0;

  /// Empty-state illustration.
  static const hero = 64.0;
}

/// Bright teal seed; Material 3 derives the tonal palette (dark mode too).
const _seed = Color(0xFF1D9E75);

ThemeData appTheme({Brightness brightness = Brightness.light}) {
  final light = brightness == Brightness.light;
  final base = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  // White page with pale teal containers in light mode; the generated
  // tones stay for dark mode.
  final scheme = light
      ? base.copyWith(
          surface: Colors.white,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF2FAF7),
          surfaceContainer: const Color(0xFFE9F6F1),
          surfaceContainerHigh: const Color(0xFFE1F5EE),
          surfaceContainerHighest: const Color(0xFFD6EFE6),
          primaryContainer: const Color(0xFFE1F5EE),
          onPrimaryContainer: const Color(0xFF04342C),
          outlineVariant: const Color(0xFFCFE3DC),
        )
      : base;
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
  // Depth: soft teal shadows lift buttons and tiles off the white page.
  final shadow = scheme.primary.withValues(alpha: light ? 0.28 : 0.5);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
          color: scheme.onSurface, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.2),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: const InputDecorationTheme(isDense: true, border: UnderlineInputBorder()),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48), shape: pill, elevation: 3, shadowColor: shadow),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: pill,
          side: BorderSide(color: scheme.primary),
          backgroundColor: scheme.surface,
          elevation: 2,
          shadowColor: shadow),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: pill)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
          shape: pill, selectedBackgroundColor: scheme.primaryContainer),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shadowColor: shadow,
      surfaceTintColor: Colors.transparent,
      color: scheme.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
    ),
  );
}
