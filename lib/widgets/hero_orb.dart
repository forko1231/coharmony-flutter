import 'package:flutter/material.dart';
import 'app_icon.dart';

/// A gradient "orb" hero: a soft halo behind a rounded core holding a white SVG
/// icon. Used across the onboarding screens. Sizes default to the 120/84 hero
/// but can be overridden.
class HeroOrb extends StatelessWidget {
  final List<Color> gradient;

  /// Either a tinted SVG [icon] name OR a custom [child] (e.g. a "✓" Text).
  final String? icon;
  final Widget? child;
  final double haloSize;
  final double coreSize;
  final double coreRadius;
  final double iconSize;

  const HeroOrb({
    super.key,
    required this.gradient,
    this.icon,
    this.child,
    this.haloSize = 120,
    this.coreSize = 84,
    this.coreRadius = 28,
    this.iconSize = 40,
  }) : assert(icon != null || child != null, 'HeroOrb needs an icon or a child');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: haloSize,
      height: haloSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 0.18,
            child: Container(
              width: haloSize,
              height: haloSize,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
                borderRadius: BorderRadius.circular(haloSize / 2),
              ),
            ),
          ),
          Container(
            width: coreSize,
            height: coreSize,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
              borderRadius: BorderRadius.circular(coreRadius),
              boxShadow: [
                BoxShadow(color: gradient.first.withValues(alpha: 0.35), offset: const Offset(0, 8), blurRadius: 20),
              ],
            ),
            child: Center(child: child ?? AppIcon(icon!, size: iconSize, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
