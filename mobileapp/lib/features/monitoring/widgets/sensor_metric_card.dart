import 'package:biomass_iot_app/app/app_icons.dart';
import 'package:biomass_iot_app/core/widgets/glowing_card.dart';
import 'package:flutter/material.dart';

class SensorMetricCard extends StatelessWidget {
  const SensorMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.color,
    required this.theme,
    this.decimals = 0,
    this.isCompact = false,
    this.maxVal = 100.0,
    this.statusText,
  });

  final String title;
  final double? value;
  final String suffix;
  final IconData icon;
  final Color color;
  final ThemeData theme;
  final int decimals;
  final bool isCompact;
  final double maxVal;
  final String? statusText;

  @override
  Widget build(BuildContext context) {
    final isWarmingUp = statusText != null;
    final isFault = value == null && !isWarmingUp;
    final displayColor = isFault || isWarmingUp ? Colors.amber : color;
    return SizedBox(
      height: isCompact ? 152 : 176,
      child: GlowingCard(
        glowColor: displayColor,
        padding: EdgeInsets.all(isCompact ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: isCompact ? 40 : 48,
                    height: isCompact ? 40 : 48,
                    decoration: BoxDecoration(
                      color: displayColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!isFault && !isWarmingUp)
                          TweenAnimationBuilder<double>(
                            duration: const Duration(seconds: 1),
                            curve: Curves.easeOutExpo,
                            tween: Tween<double>(
                              begin: 0.0,
                              end: (value! / maxVal).clamp(0.0, 1.0),
                            ),
                            builder: (context, progress, _) =>
                                CircularProgressIndicator(
                                  value: progress,
                                  backgroundColor: displayColor.withValues(
                                    alpha: 0.1,
                                  ),
                                  color: displayColor,
                                  strokeWidth: 3,
                                ),
                          ),
                        Icon(
                          isFault ? AppIcons.warning : icon,
                          color: displayColor,
                          size: isCompact ? 20 : 24,
                        ),
                      ],
                    ),
                  ),
                  if (isFault || isWarmingUp)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: isCompact ? 92 : 130,
                            child: Text(
                              statusText ?? 'Sensor fault',
                              style: TextStyle(
                                color: displayColor,
                                fontSize: isCompact ? 11 : 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey,
                fontSize: isCompact ? 12 : 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            if (isFault || isWarmingUp)
              Text(
                '--',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontSize: isCompact ? 24 : 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              )
            else
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutExpo,
                tween: Tween<double>(begin: 0.0, end: value!),
                builder: (context, animatedValue, _) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${animatedValue.toStringAsFixed(decimals)}$suffix',
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: isCompact ? 24 : 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
