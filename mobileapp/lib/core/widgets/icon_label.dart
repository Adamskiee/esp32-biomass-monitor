import 'package:flutter/material.dart';

class IconLabel extends StatelessWidget {
  const IconLabel({
    super.key,
    required this.icon,
    required this.label,
    this.style,
    this.color,
    this.iconSize = 20,
  });

  final IconData icon;
  final String label;
  final TextStyle? style;
  final Color? color;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: iconSize, color: color ?? style?.color),
      const SizedBox(width: 8),
      Flexible(child: Text(label, style: style)),
    ],
  );
}
