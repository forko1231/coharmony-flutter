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
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final resolved = padding.resolve(Directionality.of(context));
    // Keyboard down: keep the base bottom gap + the Android nav-bar / iOS
    // home-indicator inset so the action never sits under the system bar.
    // Keyboard up: the keyboard already covers that inset, so collapse to a
    // small gap instead of floating the action ~70px above the keyboard.
    final bottom = keyboardUp
        ? 12.0
        : resolved.bottom + MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(resolved.left, resolved.top, resolved.right, bottom),
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
