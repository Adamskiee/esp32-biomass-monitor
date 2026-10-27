import 'dart:ui' show Tristate;

import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/core/widgets/glowing_card.dart';
import 'package:biomass_iot_app/features/alerts/alerts_controller.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:flutter/material.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/features/alerts/alerts_tab.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends AlertsController {
  _Controller() : super(AlertsStore(AppDatabase()));
  @override
  Future<void> load() async {}
  String? requestedSeverity;

  @override
  Future<void> setSeverity(String? severity) async {
    requestedSeverity = severity;
  }
}

class _IdleAlertsController extends AlertsController {
  _IdleAlertsController() : super(AlertsStore(AppDatabase()));

  @override
  Future<void> load() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets('filter colors and selection stay consistent in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _Controller();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            cardColor: brightness == Brightness.dark
                ? AppTheme.cardDark
                : Colors.white,
          ),
          home: AlertsTab(controller: controller),
        ),
      );
      final originalColors = <String, Color>{};
      for (final label in ['All', 'Info', 'Warning', 'Critical']) {
        final button = find.widgetWithText(TextButton, label);
        final icon = find.descendant(of: button, matching: find.byType(Icon));
        final text = find.descendant(
          of: find.text(label),
          matching: find.byType(RichText),
        );
        final color = IconTheme.of(tester.element(icon)).color!;
        expect(tester.widget<RichText>(text).text.style!.color, color);
        originalColors[label] = color;
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(button).flagsCollection.isSelected,
          Tristate.isTrue,
        );
        final style = tester.widget<TextButton>(button).style!;
        final background = style.backgroundColor!.resolve({})!;
        final contrast =
            (color.computeLuminance() + 0.05) /
            (background.computeLuminance() + 0.05);
        expect(
          contrast >= 4.5 || contrast <= 1 / 4.5,
          isTrue,
          reason: '$label needs readable text contrast',
        );
        expect(IconTheme.of(tester.element(icon)).color, color);
      }
      expect(originalColors.values.toSet(), hasLength(4));
      expect(controller.requestedSeverity, 'critical');
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(controller.requestedSeverity, isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      controller.dispose();
    });
  }

  test('reserves space above the mobile navigation bar', () {
    expect(alertListBottomInset(width: 450, safeAreaBottom: 24), 160);
  });

  test('uses a normal inset beside desktop navigation', () {
    expect(alertListBottomInset(width: 900, safeAreaBottom: 24), 32);
  });
  testWidgets('summary header stacks a full-width action on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _IdleAlertsController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.getLightTheme(),
        home: AlertsTab(controller: controller),
      ),
    );
    await tester.pump();

    final header = tester.getRect(find.byType(GlowingCard));
    final action = tester.getRect(find.byType(ElevatedButton));
    final summary = tester.getRect(find.text('0 alerts today'));

    expect(header.width - action.width, lessThanOrEqualTo(34));
    expect(action.top, greaterThan(summary.bottom));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('summary header keeps its action beside the summary on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _IdleAlertsController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.getLightTheme(),
        home: AlertsTab(controller: controller),
      ),
    );
    await tester.pump();

    final action = tester.getRect(find.byType(ElevatedButton));
    final summary = tester.getRect(find.text('0 alerts today'));

    expect(action.left, greaterThan(summary.right));
    expect(action.top, lessThan(summary.bottom));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
