import 'package:flutter/material.dart';

import '../data/coverage.dart';

/// App theme.
///
/// Dark by default: this app is used in gyms, often in low light, and a bright
/// white screen between sets is unpleasant. Both schemes are defined so the
/// system setting is respected.
class AppTheme {
  static const seed = Color(0xFF4F7DF3);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}

/// Colours for the coverage map and its legend.
///
/// Deliberately not a red/green pair: the point is "how much work did this get",
/// not "good/bad", and red/green also fails for the most common form of colour
/// blindness. The scale runs from a flat unlit surface through a mid tone to the
/// full accent, so it reads as intensity even in greyscale.
class CoverageColors {
  static Color forBand(CoverageBand band, ColorScheme scheme) =>
      switch (band) {
        CoverageBand.none => scheme.surfaceContainerHighest,
        CoverageBand.light => Color.lerp(
          scheme.surfaceContainerHighest,
          scheme.primary,
          0.45,
        )!,
        CoverageBand.solid => scheme.primary,
      };

  static Color outline(ColorScheme scheme) => scheme.outlineVariant;

  static String label(CoverageBand band) => switch (band) {
    CoverageBand.none => 'Not trained',
    CoverageBand.light => 'Light',
    CoverageBand.solid => 'Trained',
  };
}
