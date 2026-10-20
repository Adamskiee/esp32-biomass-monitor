import 'package:biomass_iot_app/core/widgets/loading_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shimmer animates only when motion is enabled', (tester) async {
    Widget host(bool reducedMotion) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: const SkeletonShimmer(
          child: LoadingSkeleton(width: 120, height: 24),
        ),
      ),
    );

    await tester.pumpWidget(host(false));
    expect(find.byType(ShaderMask), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byType(LoadingSkeleton), findsOneWidget);
  });

  testWidgets('renders a rounded placeholder at the requested size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LoadingSkeleton(width: 120, height: 24, borderRadius: 12),
        ),
      ),
    );

    final placeholder = tester.widget<Container>(
      find.byKey(const Key('loading-skeleton')),
    );
    final decoration = placeholder.decoration! as BoxDecoration;

    expect(find.byKey(const Key('loading-skeleton')), findsOneWidget);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(
      tester.getSize(find.byKey(const Key('loading-skeleton'))),
      const Size(120, 24),
    );
  });
}
