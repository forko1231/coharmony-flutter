import 'package:flutter/material.dart';
import '../widgets/motion.dart';
import 'app_colors.dart';
import 'app_palette.dart';

/// Builds the light/dark [ThemeData]. Screens read brand accents from [AppColors]
/// and theme-aware colors from `context.palette` ([AppPalette]).
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light, AppPalette.light);
  static ThemeData get dark => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryBlue,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.primaryBlue,
      surface: palette.surface,
      error: AppColors.dangerRed,
    );

    final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: colorScheme);

    return base.copyWith(
      scaffoldBackgroundColor: palette.background,
      extensions: [palette],
      // TODO(font): MAUI default font from Styles.xaml — reconcile once confirmed.
      textTheme: base.textTheme.apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      iconTheme: IconThemeData(color: palette.textSecondary),
      dividerColor: palette.border,
      pageTransitionsTheme: appPageTransitionsTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
    );
  }
}
