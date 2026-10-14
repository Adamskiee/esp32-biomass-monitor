import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:flutter/cupertino.dart';

class AlertPresentation {
  const AlertPresentation({required this.color, required this.icon});

  final Color color;
  final IconData icon;
}

AlertPresentation alertPresentationForSeverity(String severity) {
  return switch (severity) {
    'critical' => const AlertPresentation(
      color: AppTheme.neonRed,
      icon: CupertinoIcons.exclamationmark_octagon_fill,
    ),
    'warning' => const AlertPresentation(
      color: AppTheme.neonOrange,
      icon: CupertinoIcons.exclamationmark_triangle_fill,
    ),
    _ => const AlertPresentation(
      color: AppTheme.neonBlue,
      icon: CupertinoIcons.info_circle_fill,
    ),
  };
}
