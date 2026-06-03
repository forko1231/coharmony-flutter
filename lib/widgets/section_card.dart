import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'app_icon.dart';

/// An elevated rounded card with a tinted icon + title/subtitle header above a
/// body — the recurring MAUI `<Border RoundRectangle 24>` "section" pattern.
class SectionCard extends StatelessWidget {
  final String iconName;
  final Color iconBg;
  final Color iconTint;
  final String title;
  final String? subtitle;
  final Widget child;
  final double boxSize;
  final double titleSize;

  const SectionCard({
    super.key,
    required this.iconName,
    required this.iconBg,
    required this.iconTint,
    required this.title,
    this.subtitle,
    required this.child,
    this.boxSize = 48,
    this.titleSize = 17,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.06),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: boxSize,
                height: boxSize,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
                child: Center(child: AppIcon(iconName, size: boxSize * 0.5, color: iconTint)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}
