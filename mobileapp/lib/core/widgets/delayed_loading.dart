import 'dart:async';

import 'package:flutter/material.dart';

import 'loading_skeleton.dart';

class DelayedLoading extends StatefulWidget {
  const DelayedLoading({
    super.key,
    required this.isLoading,
    required this.placeholder,
    required this.child,
    this.hasContent = false,
  });

  final bool isLoading;
  final bool hasContent;
  final Widget placeholder;
  final Widget child;

  @override
  State<DelayedLoading> createState() => _DelayedLoadingState();
}

class _DelayedLoadingState extends State<DelayedLoading> {
  Timer? _delay;
  bool _showSkeleton = false;
  bool _fadeContent = false;

  bool get _waiting => widget.isLoading && !widget.hasContent;

  @override
  void initState() {
    super.initState();
    if (_waiting) _startDelay();
  }

  void _startDelay() {
    _showSkeleton = false;
    _fadeContent = false;
    _delay = Timer(const Duration(milliseconds: 200), () {
      setState(() => _showSkeleton = true);
    });
  }

  @override
  void didUpdateWidget(covariant DelayedLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasWaiting = oldWidget.isLoading && !oldWidget.hasContent;
    if (wasWaiting == _waiting) return;
    _delay?.cancel();
    if (_waiting) {
      _startDelay();
    } else {
      _fadeContent = _showSkeleton;
      _showSkeleton = false;
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_waiting) {
      if (!_showSkeleton) return const SizedBox.shrink();
      return Semantics(
        label: 'Loading',
        liveRegion: true,
        child: ExcludeSemantics(
          child: SkeletonShimmer(child: widget.placeholder),
        ),
      );
    }
    if (!_fadeContent || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: widget.child,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
    );
  }
}
