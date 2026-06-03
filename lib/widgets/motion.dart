import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Motion baseline for the app — shared transition + interaction primitives so
/// the whole app moves with one consistent, calm language (the payoff of moving
/// off MAUI's native-control rendering). Two pieces:
///   • [AppPageTransitionsBuilder] — a subtle fade + rise used for every route.
///   • [Pressable] — a scale-down + haptic wrapper for tappable cards/buttons.

/// A gentle "fade-through + rise": the incoming page fades in while sliding up a
/// few px and easing from 98% scale; the outgoing page just fades. Platform-
/// agnostic and quieter than a full slide, which suits a calm utility app.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.018), end: Offset.zero)
            .animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

/// App-wide scroll behaviour: the iOS rubber-band overscroll on every platform
/// (Android defaults to a flat clamp), and the overscroll glow suppressed for a
/// cleaner native feel. Widgets that set their own `physics:` still win, so the
/// skeletons' non-scrollable lists are unaffected.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child; // no Material glow; bounce conveys the edge
}

/// Page transitions theme applying [AppPageTransitionsBuilder] on every platform.
const appPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.iOS: AppPageTransitionsBuilder(),
    TargetPlatform.android: AppPageTransitionsBuilder(),
    TargetPlatform.macOS: AppPageTransitionsBuilder(),
    TargetPlatform.windows: AppPageTransitionsBuilder(),
    TargetPlatform.linux: AppPageTransitionsBuilder(),
    TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
  },
);

/// Wraps any tappable surface so it dips slightly while pressed and fires a
/// light haptic on tap — the micro-feedback that makes taps feel physical.
/// Drop-in replacement for a `GestureDetector(onTap:)` around a card/button.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Pressed-state scale (1.0 = no shrink). Smaller = more pronounced dip.
  final double scale;

  /// Whether to fire [HapticFeedback.lightImpact] on tap.
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
