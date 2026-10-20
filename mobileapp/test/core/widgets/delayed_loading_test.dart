import 'package:biomass_iot_app/core/widgets/delayed_loading.dart';
import 'package:biomass_iot_app/core/widgets/loading_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  bool loading = true,
  bool hasContent = false,
  bool reducedMotion = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: DelayedLoading(
      isLoading: loading,
      hasContent: hasContent,
      placeholder: const LoadingSkeleton(width: 100, height: 20),
      child: TextButton(onPressed: () {}, child: const Text('Content')),
    ),
  ),
);

void main() {
  testWidgets('available content appears immediately without a skeleton', (
    tester,
  ) async {
    await tester.pumpWidget(_host(loading: false));
    expect(find.text('Content').hitTestable(), findsOneWidget);
    expect(find.byType(LoadingSkeleton), findsNothing);
  });

  testWidgets('a slow request shows skeletons only after 200 ms', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 199));
    expect(find.byType(LoadingSkeleton), findsNothing);
    expect(find.text('Content'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(LoadingSkeleton), findsOneWidget);
    await tester.pumpWidget(_host(loading: false));
    expect(find.byType(LoadingSkeleton), findsNothing);
    expect(find.text('Content'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 151));
    expect(find.text('Content').hitTestable(), findsOneWidget);
  });

  testWidgets('fast requests never flash a skeleton or fade content', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(_host(loading: false));
    expect(find.text('Content').hitTestable(), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LoadingSkeleton), findsNothing);
  });

  testWidgets('background refresh keeps existing content mounted and usable', (
    tester,
  ) async {
    await tester.pumpWidget(_host(loading: false, hasContent: true));
    final element = tester.element(find.text('Content'));
    await tester.pumpWidget(_host(hasContent: true));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LoadingSkeleton), findsNothing);
    expect(find.text('Content').hitTestable(), findsOneWidget);
    expect(tester.element(find.text('Content')), same(element));
  });

  testWidgets('each new request gets its own delay and cancels on disposal', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(_host(loading: false));
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(LoadingSkeleton), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion skips shimmer and reveals completed loads immediately',
    (tester) async {
      await tester.pumpWidget(_host(reducedMotion: true));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(LoadingSkeleton), findsOneWidget);
      expect(find.byType(ShaderMask), findsNothing);
      await tester.pumpWidget(_host(loading: false, reducedMotion: true));
      expect(find.text('Content').hitTestable(), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);
    },
  );
}
