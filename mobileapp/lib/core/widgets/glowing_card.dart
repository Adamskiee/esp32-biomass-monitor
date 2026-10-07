import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:flutter/material.dart';

class GlowingCard extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final EdgeInsetsGeometry padding;

  const GlowingCard({
    super.key,
    required this.child,
    this.glowColor = AppTheme.neonGreen,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  State<GlowingCard> createState() => _GlowingCardState();
}

class _GlowingCardState extends State<GlowingCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isHovered
                  ? widget.glowColor.withValues(alpha: 0.8)
                  : theme.dividerColor,
              width: _isHovered ? 1.5 : 1.0,
            ),
            gradient: LinearGradient(
              colors: [
                widget.glowColor.withValues(
                  alpha: _isHovered ? 0.15 : (isDark ? 0.02 : 0.05),
                ),
                Colors.transparent,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withValues(
                  alpha: _isHovered ? 0.3 : 0.05,
                ),
                blurRadius: _isHovered ? 25.0 : 10.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
