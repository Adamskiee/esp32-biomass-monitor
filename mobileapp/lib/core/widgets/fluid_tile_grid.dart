import 'package:flutter/widgets.dart';

class FluidTileGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final double spacing;

  const FluidTileGrid({
    super.key,
    required this.children,
    this.minTileWidth = 160.0,
    this.spacing = 16.0,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      var crossAxisCount =
          ((constraints.maxWidth + spacing) / (minTileWidth + spacing)).floor();
      if (crossAxisCount < 1) crossAxisCount = 1;
      var tileWidth =
          ((constraints.maxWidth + spacing) / crossAxisCount) - spacing;
      tileWidth -= 0.01;
      if (tileWidth < 0) tileWidth = 0;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: children
            .map((child) => SizedBox(width: tileWidth, child: child))
            .toList(),
      );
    },
  );
}
