import 'package:flutter/material.dart';

/// Pitch black theme: black surfaces, white text, greys for containers.
/// Color is left to meaning (streak orange, XP amber, right and wrong).
ThemeData blackTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Colors.white,
    onPrimary: Colors.black,
    primaryContainer: Color(0xFF2A2A2A),
    onPrimaryContainer: Colors.white,
    secondary: Color(0xFFBDBDBD),
    onSecondary: Colors.black,
    secondaryContainer: Color(0xFF262626),
    onSecondaryContainer: Colors.white,
    tertiary: Color(0xFFFFC107),
    onTertiary: Colors.black,
    error: Color(0xFFFF6B6B),
    onError: Colors.black,
    surface: Colors.black,
    onSurface: Colors.white,
    onSurfaceVariant: Color(0xFFB0B0B0),
    surfaceContainerLowest: Colors.black,
    surfaceContainerLow: Color(0xFF0D0D0D),
    surfaceContainer: Color(0xFF121212),
    surfaceContainerHigh: Color(0xFF1A1A1A),
    surfaceContainerHighest: Color(0xFF242424),
    outline: Color(0xFF5A5A5A),
    outlineVariant: Color(0xFF2E2E2E),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.black,
    canvasColor: Colors.black,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
