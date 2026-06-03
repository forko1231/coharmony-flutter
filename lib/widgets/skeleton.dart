import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Shimmering skeleton placeholders — the Flutter upgrade of MAUI's `SkeletonBox`
/// (which only pulsed opacity). Here a soft highlight band sweeps across the
/// base colour, the modern iOS/Material loading look.
///
/// Usage: wrap a tree of [Skeleton] boxes in a single [Shimmer] so they all
/// share one synchronised sweep:
/// ```dart
/// Shimmer(child: Column(children: [Skeleton(height: 16, width: 120), ...]))
/// ```
/// A handful of ready-made layouts ([SkeletonCardList], [SkeletonListTiles])
/// cover the common "loading a list of cards" case.

/// Crossfades from a [skeleton] placeholder to real [child] content once
/// [loading] flips false, so content eases in instead of popping. Drop-in
/// around any `loading ? skeleton : content` branch.
class LoadingSwitcher extends StatelessWidget {
  const LoadingSwitcher({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.child,
    this.duration = const Duration(milliseconds: 350),
  });

  final bool loading;
  final Widget skeleton;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      child: loading
          ? KeyedSubtree(key: const ValueKey('skeleton'), child: skeleton)
          : KeyedSubtree(key: const ValueKey('content'), child: child),
    );
  }
}

/// Drives a single shared sweep animation and exposes it to descendant
/// [Skeleton]s via an [InheritedWidget], so every box in one screen shimmers in
/// lockstep instead of each running its own timer.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  static _ShimmerState? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.state;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(Shimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get value => _controller.value;
  Listenable get listenable => _controller;

  @override
  Widget build(BuildContext context) => _ShimmerScope(state: this, child: widget.child);
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.state, required super.child});
  final _ShimmerState state;

  @override
  bool updateShouldNotify(_ShimmerScope oldWidget) => false;
}

/// A single rounded placeholder block. Repaints with the ancestor [Shimmer]'s
/// sweep; falls back to a flat base colour if there's no [Shimmer] ancestor.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 8,
    this.shape = BoxShape.rectangle,
  });

  /// Convenience for a circular avatar/icon placeholder of [size]x[size].
  const Skeleton.circle({super.key, required double size})
      : width = size,
        height = size,
        borderRadius = 0,
        shape = BoxShape.circle;

  final double? width;
  final double height;
  final double borderRadius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shimmer = Shimmer._of(context);
    final base = palette.skeletonBase;
    final highlight = palette.skeletonShimmer;

    Widget box(double t) {
      // t in [0,1] → sweep a soft highlight band left→right across the box.
      final dx = (t * 2.0) - 1.0; // -1 → 1
      final gradient = LinearGradient(
        begin: Alignment(-1.0 - 0.3, -0.3),
        end: Alignment(1.0 + 0.3, 0.3),
        colors: [base, highlight, base],
        stops: const [0.35, 0.5, 0.65],
        transform: _SlideGradient(dx),
      );
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: shimmer == null ? null : gradient,
          color: shimmer == null ? base : null,
          shape: shape,
          borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(borderRadius),
        ),
      );
    }

    if (shimmer == null) return box(0);
    return AnimatedBuilder(
      animation: shimmer.listenable,
      builder: (_, _) => box(shimmer.value),
    );
  }
}

/// Translates a gradient horizontally by a fraction of its bounds, used to slide
/// the highlight band across the box as the sweep animates.
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.fraction);
  final double fraction;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * fraction, 0, 0);
}

/// A ready-made "loading list of cards" placeholder — N rounded card blocks,
/// each with an icon + two text lines, wrapped in a synchronised [Shimmer].
class SkeletonCardList extends StatelessWidget {
  const SkeletonCardList({
    super.key,
    this.count = 5,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
    this.cardHeight = 76,
  });

  final int count;
  final EdgeInsets padding;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Shimmer(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => Container(
          height: cardHeight,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Skeleton(width: 44, height: 44, borderRadius: 12),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Skeleton(width: 140, height: 14),
                    SizedBox(height: 8),
                    Skeleton(width: 90, height: 12),
                  ],
                ),
              ),
              const Skeleton(width: 56, height: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// A month-grid placeholder for the schedule / custody calendars: a title block,
/// a weekday header row, then [weeks] rows of seven day cells.
class SkeletonCalendar extends StatelessWidget {
  const SkeletonCalendar({super.key, this.weeks = 5});
  final int weeks;

  @override
  Widget build(BuildContext context) {
    Widget cell() => const Expanded(
          child: Padding(
            padding: EdgeInsets.all(3),
            child: Skeleton(height: 40, borderRadius: 10),
          ),
        );
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Skeleton(width: 180, height: 22, borderRadius: 11)),
            const SizedBox(height: 20),
            Row(
              children: [for (int i = 0; i < 7; i++) const Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(3),
                    child: Center(child: Skeleton(width: 24, height: 12)),
                  ))],
            ),
            const SizedBox(height: 8),
            for (int w = 0; w < weeks; w++)
              Row(children: [for (int d = 0; d < 7; d++) cell()]),
          ],
        ),
      ),
    );
  }
}

/// Dashboard placeholder: a two-up stat row followed by full-width cards,
/// matching the main menu's layout while it loads.
class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({super.key, this.cards = 3});
  final int cards;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget block({double height = 88}) => Container(
          height: height,
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Skeleton(width: 60, height: 12),
              SizedBox(height: 10),
              Skeleton(width: 110, height: 16),
            ],
          ),
        );
    return Shimmer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: block()),
                const SizedBox(width: 12),
                Expanded(child: block()),
              ],
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < cards; i++) ...[
              block(height: 72),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lightweight list-tile skeletons (avatar + two lines) for chat/contact lists.
class SkeletonListTiles extends StatelessWidget {
  const SkeletonListTiles({super.key, this.count = 8});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        itemBuilder: (_, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Skeleton.circle(size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Skeleton(width: 160, height: 14),
                    SizedBox(height: 8),
                    Skeleton(width: 220, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
