import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'app_icon.dart';

/// Standard page header: a surface bar with a soft bottom shadow, an optional
/// rounded back button, a centered title + subtitle, and an optional trailing
/// widget. Mirrors the repeated MAUI header `<Border>` across the app.
class AppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Extend the header's coloured background up behind the status bar / Dynamic
    // Island, but push its CONTENT below the safe-area inset so the title isn't
    // smooshed under the island. (MAUI used an explicit safe-area top padding; the
    // idiomatic Flutter equivalent is adding the device top inset here.)
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return Container(
      padding: padding.add(EdgeInsets.only(top: topInset)),
      decoration: BoxDecoration(
        color: palette.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
            offset: const Offset(0, 4),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        children: [
          if (onBack != null)
            _RoundButton(onTap: onBack!, child: AppIcon('icon_back', size: 20, color: palette.textPrimary))
          else
            const SizedBox(width: 44),
          Expanded(
            child: Column(
              children: [
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                ],
              ],
            ),
          ),
          trailing ?? const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _RoundButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: child),
      ),
    );
  }
}
