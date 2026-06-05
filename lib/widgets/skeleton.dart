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
      // AnimatedSwitcher's default layout stacks children with Alignment.center and
      // hands them LOOSE constraints — so a SingleChildScrollView child shrink-wraps
      // to its content height and gets vertically centered, leaving a gap under the
      // header when there isn't enough content to scroll. Top-align instead so loaded
      // content always pins to the top. Fixes the "floating/centered list" everywhere.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [
          ...previousChildren,
          ?currentChild,
        ],
      ),
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

/// Placeholder for the custody schedule editor: a pattern-config bar, a legend
/// strip, then [weeks] bordered week cards (weekday header + a row of 7 tall day
/// cells), matching the real editor's structure while it loads.
class SkeletonCalendar extends StatelessWidget {
  const SkeletonCalendar({super.key, this.weeks = 2});
  final int weeks;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget framed(Widget child) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: child,
        );

    Widget weekCard() => framed(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Skeleton(width: 70, height: 15),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (int i = 0; i < 7; i++)
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Center(child: Skeleton(width: 22, height: 11)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (int d = 0; d < 7; d++)
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Skeleton(height: 64, borderRadius: 12),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );

    return Shimmer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pattern config bar
            framed(Row(
              children: const [
                Expanded(child: Skeleton(width: 160, height: 15)),
                Skeleton(width: 70, height: 16),
              ],
            )),
            const SizedBox(height: 16),
            // Legend strip
            Center(
              child: Wrap(
                spacing: 16,
                children: const [
                  Skeleton(width: 50, height: 14),
                  Skeleton(width: 50, height: 14),
                  Skeleton(width: 50, height: 14),
                  Skeleton(width: 50, height: 14),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (int w = 0; w < weeks; w++) ...[
              weekCard(),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dashboard placeholder — mirrors the real main-menu layout: a two-up stat row
/// (icon + label + value), a calendar card (header + weekday row + month grid),
/// then list-style cards (header + a few icon rows) for upcoming / payments /
/// messages. Much closer to the loaded screen than a stack of plain blocks.
class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget card({required Widget child}) => Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(20),
          child: child,
        );

    // Two-up stat card: icon square + a short label + a value line.
    Widget statCard() => card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Skeleton(width: 44, height: 44, borderRadius: 12),
              SizedBox(height: 14),
              Skeleton(width: 56, height: 12),
              SizedBox(height: 10),
              Skeleton(width: 96, height: 18),
            ],
          ),
        );

    // Calendar card: title/subtitle + "View All" pill, weekday header, 5 week rows.
    Widget calendarCell() => const Expanded(
          child: Padding(
            padding: EdgeInsets.all(3),
            child: Skeleton(height: 38, borderRadius: 10),
          ),
        );
    Widget calendarCard() => card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(width: 110, height: 20),
                        SizedBox(height: 6),
                        Skeleton(width: 80, height: 13),
                      ],
                    ),
                  ),
                  Skeleton(width: 88, height: 36, borderRadius: 12),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (int i = 0; i < 7; i++)
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(3),
                        child: Center(child: Skeleton(width: 22, height: 11)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              for (int w = 0; w < 5; w++)
                Row(children: [for (int d = 0; d < 7; d++) calendarCell()]),
            ],
          ),
        );

    // List card: section title + N rows (icon + two text lines + trailing chip).
    Widget row() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: const [
              Skeleton(width: 40, height: 40, borderRadius: 10),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: 130, height: 13),
                    SizedBox(height: 7),
                    Skeleton(width: 80, height: 11),
                  ],
                ),
              ),
              Skeleton(width: 48, height: 16),
            ],
          ),
        );
    Widget listCard({int rows = 3}) => card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Skeleton(width: 140, height: 18),
              const SizedBox(height: 8),
              for (int i = 0; i < rows; i++) row(),
            ],
          ),
        );

    return Shimmer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: statCard()),
                  const SizedBox(width: 12),
                  Expanded(child: statCard()),
                ],
              ),
            ),
            const SizedBox(height: 20),
            calendarCard(),
            const SizedBox(height: 20),
            listCard(rows: 3),
            const SizedBox(height: 20),
            listCard(rows: 2),
          ],
        ),
      ),
    );
  }
}

/// Month-grid placeholder for the schedule (month-view) page: a weekday header
/// row, a 6×7 grid of square day cells, then a legend strip — mirrors the real
/// month calendar while it loads.
class SkeletonMonthGrid extends StatelessWidget {
  const SkeletonMonthGrid({super.key, this.rows = 6});
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        physics: const NeverScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (int i = 0; i < 7; i++)
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(3),
                          child: Center(child: Skeleton(width: 22, height: 12)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                for (int w = 0; w < rows; w++)
                  Row(
                    children: [
                      for (int d = 0; d < 7; d++)
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(3),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Skeleton(borderRadius: 10),
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 20),
                Center(
                  child: Wrap(
                    spacing: 16,
                    children: const [
                      Skeleton(width: 50, height: 14),
                      Skeleton(width: 50, height: 14),
                      Skeleton(width: 50, height: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
