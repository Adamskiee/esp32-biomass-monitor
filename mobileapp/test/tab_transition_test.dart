import 'package:biomass_iot_app/tab_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pages = [
  SizedBox(key: ValueKey('page-0'), width: 100, height: 100),
  SizedBox(key: ValueKey('page-1'), width: 100, height: 100),
  SizedBox(key: ValueKey('page-2'), width: 100, height: 100),
];

Widget _host(int index) => MaterialApp(
  home: TabTransition(currentIndex: index, children: _pages),
);

Finder _page(int index) => find.byKey(ValueKey('page-$index'));

void main() {
  testWidgets('overlaps pages until the 300 ms transition completes', (
    tester,
  ) async {
    await tester.pumpWidget(_host(0));
    expect(_page(0), findsOneWidget);
    expect(_page(1), findsNothing);

    await tester.pumpWidget(_host(1));
    await tester.pump(const Duration(milliseconds: 299));
    expect(_page(0), findsOneWidget);
    expect(_page(1), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(_page(0), findsNothing);
    expect(_page(1), findsOneWidget);
  });

  testWidgets('preserves the fade and scale transition curves', (tester) async {
    await tester.pumpWidget(_host(0));
    await tester.pumpWidget(_host(1));

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, const Duration(milliseconds: 300));
    expect(switcher.switchInCurve, Curves.easeOut);
    expect(switcher.switchOutCurve, Curves.easeIn);

    FadeTransition incomingFade() => tester.widget<FadeTransition>(
      find.ancestor(
        of: _page(1),
        matching: find.descendant(
          of: find.byType(TabTransition),
          matching: find.byType(FadeTransition),
        ),
      ),
    );
    ScaleTransition incomingScale() => tester.widget<ScaleTransition>(
      find.ancestor(of: _page(1), matching: find.byType(ScaleTransition)),
    );

    expect(incomingFade().opacity.value, 0);
    expect(incomingScale().scale.value, 0.95);

    await tester.pump(const Duration(milliseconds: 150));
    final easedProgress = Curves.easeOut.transform(0.5);
    expect(incomingFade().opacity.value, closeTo(easedProgress, 0.0001));
    expect(
      incomingScale().scale.value,
      closeTo(
        0.95 + 0.05 * Curves.easeOutCubic.transform(easedProgress),
        0.0001,
      ),
    );

    await tester.pumpAndSettle();
    expect(incomingFade().opacity.value, 1);
    expect(incomingScale().scale.value, 1);
  });

  testWidgets('isolates every active page with a repaint boundary', (
    tester,
  ) async {
    await tester.pumpWidget(_host(0));
    await tester.pumpWidget(_host(1));
    await tester.pump(const Duration(milliseconds: 100));

    final transitionBoundaries = find.descendant(
      of: find.byType(TabTransition),
      matching: find.byType(RepaintBoundary),
    );
    expect(transitionBoundaries, findsNWidgets(2));
    for (final index in [0, 1]) {
      expect(
        find.ancestor(of: _page(index), matching: transitionBoundaries),
        findsOneWidget,
      );
    }
  });

  testWidgets('finishes on the latest page after a rapid selection', (
    tester,
  ) async {
    await tester.pumpWidget(_host(0));
    await tester.pumpWidget(_host(1));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(_host(2));
    await tester.pump(const Duration(milliseconds: 100));

    expect(_page(0), findsOneWidget);
    expect(_page(1), findsOneWidget);
    expect(_page(2), findsOneWidget);

    await tester.pumpAndSettle();
    expect(_page(0), findsNothing);
    expect(_page(1), findsNothing);
    expect(_page(2), findsOneWidget);
  });
}
