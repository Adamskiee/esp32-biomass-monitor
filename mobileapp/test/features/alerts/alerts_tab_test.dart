import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/core/widgets/glowing_card.dart';
import 'package:biomass_iot_app/features/alerts/alerts_controller.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:biomass_iot_app/features/alerts/alerts_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _IdleAlertsController extends AlertsController {
  _IdleAlertsController() : super(AlertsStore(AppDatabase()));

  @override
  Future<void> load() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
