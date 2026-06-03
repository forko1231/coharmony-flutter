import 'package:flutter/material.dart';

/// Raw color palette, ported 1:1 from the MAUI app's `Resources/Styles/Colors.xaml`.
///
/// Brand/semantic-accent colors are brightness-independent (single value). Surface/text/
/// border colors come in Light/Dark pairs and are surfaced per-theme through [AppPalette]
/// (see app_palette.dart), mirroring MAUI's `{AppThemeBinding Light=..., Dark=...}`.
class AppColors {
  AppColors._();

  // ── Brand / accents (brightness-independent) ──────────────────────────────
  static const primaryBlue = Color(0xFF2563EB);
  static const primaryBlueLight = Color(0xFF3B82F6); // used directly for highlights in code
  static const accentPurple = Color(0xFF7C3AED);
  static const accentTeal = Color(0xFF0D9488);
  static const successGreen = Color(0xFF10B981);
  static const successGreenLight = Color(0xFF34D399);
  static const warningAmber = Color(0xFFF59E0B);
  static const dangerRed = Color(0xFFEF4444);
  static const dangerRedLight = Color(0xFFF87171);
  static const infoBlue = Color(0xFF0EA5E9);

  // Parent-assignment colors (custody schedule cells)
  static const parentDad = Color(0xFFADD8E6); // LightBlue
  static const parentMom = Color(0xFFFFB6C1); // LightPink
  static const parentBoth = Color(0xFF9370DB); // MediumPurple

  // ── Background ─────────────────────────────────────────────────────────────
  static const backgroundLight = Color(0xFFF5F7FA);
  static const backgroundDark = Color(0xFF0A0F1C);

  // ── Surface ────────────────────────────────────────────────────────────────
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF111827);
  static const surfaceElevatedLight = Color(0xFFFFFFFF);
  static const surfaceElevatedDark = Color(0xFF1F2937);
  static const surfaceInputLight = Color(0xFFF9FAFB);
  static const surfaceInputDark = Color(0xFF111827);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const textPrimaryLight = Color(0xFF111827);
  static const textPrimaryDark = Color(0xFFF9FAFB);
  static const textSecondaryLight = Color(0xFF6B7280);
  static const textSecondaryDark = Color(0xFF9CA3AF);
  static const textMutedLight = Color(0xFF9CA3AF);
  static const textMutedDark = Color(0xFF6B7280);
  static const textPlaceholderLight = Color(0xFF9CA3AF);
  static const textPlaceholderDark = Color(0xFF6B7280);

  // ── Border ─────────────────────────────────────────────────────────────────
  static const borderLight = Color(0xFFE5E7EB);
  static const borderDark = Color(0xFF374151);

  // ── Icon background tints (brightness-independent) ─────────────────────────
  static const iconBgBlue = Color(0xFFDBEAFE);
  static const iconBgGreen = Color(0xFFDCFCE7);
  static const iconBgYellow = Color(0xFFFEF3C7);
  static const iconBgPurple = Color(0xFFF3E8FF);
  static const iconBgTeal = Color(0xFFCCFBF1);
  static const iconBgRed = Color(0xFFFEE2E2);
  static const iconBgCyan = Color(0xFFCFFAFE);

  // ── Status surfaces ─────────────────────────────────────────────────────────
  static const warningBgLight = Color(0xFFFFFBEB);
  static const warningBgDark = Color(0xFF451A03);
  static const errorBgLight = Color(0xFFFEF2F2);
  static const errorBgDark = Color(0xFF1F1416);
  static const errorBorderLight = Color(0xFFFCA5A5);
  static const errorBorderDark = Color(0xFFDC2626);
  static const successBgLight = Color(0xFFF0FDF4);
  static const successBgDark = Color(0xFF14532D);
  static const infoBgLight = Color(0xFFF0F9FF);
  static const infoBgDark = Color(0xFF0C1E2E);

  // ── Skeleton loading ────────────────────────────────────────────────────────
  static const skeletonBaseLight = Color(0xFFE5E7EB);
  static const skeletonBaseDark = Color(0xFF374151);
  static const skeletonShimmerLight = Color(0xFFF3F4F6);
  static const skeletonShimmerDark = Color(0xFF4B5563);
}
