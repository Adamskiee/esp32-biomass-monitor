import 'package:flutter/material.dart';

class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmer.stop();
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _shimmer,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          final position = -1 + _shimmer.value * 3;
          return LinearGradient(
            begin: Alignment(position - 1, -0.3),
            end: Alignment(position + 1, 0.3),
            colors: const [
              Colors.transparent,
              Color(0x26FFFFFF),
              Colors.transparent,
            ],
          ).createShader(bounds);
        },
        child: child,
      ),
    );
  }
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('loading-skeleton'),
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(borderRadius),
    ),
  );
}

class LoadingSkeletonCard extends StatelessWidget {
  const LoadingSkeletonCard({
    super.key,
    this.height = 96,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final double height;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    margin: margin,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LoadingSkeleton(width: 132, height: 16),
        Spacer(),
        LoadingSkeleton(width: 220, height: 12),
        SizedBox(height: 8),
        LoadingSkeleton(width: 96, height: 12),
      ],
    ),
  );
}
