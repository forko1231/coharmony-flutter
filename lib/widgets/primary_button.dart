import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_icon.dart';

/// The primary call-to-action: a PrimaryBlue→PrimaryBlueLight horizontal gradient
/// pill with an optional tinted SVG icon, a bold white label, and a loading state.
/// Mirrors the repeated MAUI `<Border>` gradient button (Sign In, Save, etc.).
class PrimaryGradientButton extends StatelessWidget {
  final String label;
  final String? iconName;
  final VoidCallback? onTap;
  final bool loading;
  final double height;

  /// Gradient stops (default PrimaryBlue→PrimaryBlueLight). Pass e.g. green for
  /// the Create-Account button.
  final List<Color>? colors;
  final Color? shadowColor;

  const PrimaryGradientButton({
    super.key,
    required this.label,
    this.iconName,
    this.onTap,
    this.loading = false,
    this.height = 58,
    this.colors,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = colors ?? const [AppColors.primaryBlue, AppColors.primaryBlueLight];
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (shadowColor ?? gradient.first).withValues(alpha: 0.35),
              offset: const Offset(0, 6),
              blurRadius: 16,
            ),
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (iconName != null) ...[
                      AppIcon(iconName!, size: 20, color: Colors.white),
                      const SizedBox(width: 8),
                    ],
                    Text(label,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
        ),
      ),
    );
  }
}
