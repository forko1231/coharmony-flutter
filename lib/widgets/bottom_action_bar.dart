import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// The pinned bottom panel that hosts a primary action — a surface with a large
/// top corner radius and an upward shadow. Mirrors the recurring MAUI
/// `<Border RoundRectangle 32,32,0,0>` action footer.
class BottomActionBar extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const BottomActionBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 20, 24, 36),
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.10),
            offset: const Offset(0, -6),
            blurRadius: 20,
          ),
        ],
      ),
      child: child,
    );
  }
}
