import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Theme-aware semantic colors, the Flutter equivalent of MAUI's
/// `{AppThemeBinding Light=..., Dark=...}`. Access via
/// `Theme.of(context).extension<AppPalette>()!` (or the `context.palette`
/// extension below). Brand accents (primaryBlue, successGreen, ...) are
/// brightness-independent and live on [AppColors] directly.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceInput;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textPlaceholder;
  final Color border;
  final Color warningBg;
  final Color errorBg;
  final Color errorBorder;
  final Color successBg;
  final Color infoBg;
  final Color skeletonBase;
  final Color skeletonShimmer;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceInput,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textPlaceholder,
    required this.border,
    required this.warningBg,
    required this.errorBg,
    required this.errorBorder,
    required this.successBg,
    required this.infoBg,
    required this.skeletonBase,
    required this.skeletonShimmer,
  });

  static const light = AppPalette(
    background: AppColors.backgroundLight,
    surface: AppColors.surfaceLight,
    surfaceElevated: AppColors.surfaceElevatedLight,
    surfaceInput: AppColors.surfaceInputLight,
    textPrimary: AppColors.textPrimaryLight,
    textSecondary: AppColors.textSecondaryLight,
    textMuted: AppColors.textMutedLight,
    textPlaceholder: AppColors.textPlaceholderLight,
    border: AppColors.borderLight,
    warningBg: AppColors.warningBgLight,
    errorBg: AppColors.errorBgLight,
    errorBorder: AppColors.errorBorderLight,
    successBg: AppColors.successBgLight,
    infoBg: AppColors.infoBgLight,
    skeletonBase: AppColors.skeletonBaseLight,
    skeletonShimmer: AppColors.skeletonShimmerLight,
  );

  static const dark = AppPalette(
    background: AppColors.backgroundDark,
    surface: AppColors.surfaceDark,
    surfaceElevated: AppColors.surfaceElevatedDark,
    surfaceInput: AppColors.surfaceInputDark,
    textPrimary: AppColors.textPrimaryDark,
    textSecondary: AppColors.textSecondaryDark,
    textMuted: AppColors.textMutedDark,
    textPlaceholder: AppColors.textPlaceholderDark,
    border: AppColors.borderDark,
    warningBg: AppColors.warningBgDark,
    errorBg: AppColors.errorBgDark,
    errorBorder: AppColors.errorBorderDark,
    successBg: AppColors.successBgDark,
    infoBg: AppColors.infoBgDark,
    skeletonBase: AppColors.skeletonBaseDark,
    skeletonShimmer: AppColors.skeletonShimmerDark,
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceInput,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textPlaceholder,
    Color? border,
    Color? warningBg,
    Color? errorBg,
    Color? errorBorder,
    Color? successBg,
    Color? infoBg,
    Color? skeletonBase,
    Color? skeletonShimmer,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceInput: surfaceInput ?? this.surfaceInput,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textPlaceholder: textPlaceholder ?? this.textPlaceholder,
      border: border ?? this.border,
      warningBg: warningBg ?? this.warningBg,
      errorBg: errorBg ?? this.errorBg,
      errorBorder: errorBorder ?? this.errorBorder,
      successBg: successBg ?? this.successBg,
      infoBg: infoBg ?? this.infoBg,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonShimmer: skeletonShimmer ?? this.skeletonShimmer,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceInput: Color.lerp(surfaceInput, other.surfaceInput, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textPlaceholder: Color.lerp(textPlaceholder, other.textPlaceholder, t)!,
      border: Color.lerp(border, other.border, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      errorBg: Color.lerp(errorBg, other.errorBg, t)!,
      errorBorder: Color.lerp(errorBorder, other.errorBorder, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonShimmer: Color.lerp(skeletonShimmer, other.skeletonShimmer, t)!,
    );
  }
}

/// Convenience accessor: `context.palette.surface`, `context.isDark`, etc.
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
