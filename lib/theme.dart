import 'package:flutter/material.dart';

/// Tokens. DESIGN.md is the contract; this file is its only implementation.
abstract final class AppRadius {
  static const small = 8.0;
  static const medium = 12.0;
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

// TODO(owner): seed colour is provisional (DESIGN.md §2).
const _seed = Color(0xFF1F5F5B);

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: _seed);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(isDense: true, border: UnderlineInputBorder()),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
