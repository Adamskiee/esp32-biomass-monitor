import 'package:biomass_iot_app/core/storage/database_provider.dart';
import 'package:biomass_iot_app/features/experiments/attempt.dart';
import 'package:biomass_iot_app/features/experiments/attempt_comparison_service.dart';
import 'package:biomass_iot_app/features/experiments/attempt_controller.dart';
import 'package:biomass_iot_app/features/experiments/attempt_reading.dart';
import 'package:biomass_iot_app/features/experiments/attempt_store.dart';
import 'package:biomass_iot_app/features/experiments/attempts_section.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

class _IdleTelemetry extends ChangeNotifier implements TelemetrySource {
  @override
  bool get isHardwareConnected => false;
  @override
  int get telemetryRevision => 0;
  @override
  SensorData get currentData => SensorData(timestamp: DateTime.utc(2026));
}

class _UnusedDatabaseProvider implements DatabaseProvider {
  @override
  Future<Database> get database => throw UnimplementedError();
}

class _MemoryAttemptStore extends AttemptStore {
  _MemoryAttemptStore() : super(_UnusedDatabaseProvider());

  final attempts = <Attempt>[];

  @override
  Future<void> recoverActiveAttempt() async {}

  @override
  Future<List<Attempt>> listAttempts() async => List.of(attempts);

  @override
  Future<List<AttemptReading>> listReadings(int attemptId) async => [];

  @override
  Future<void> deleteAttempt(int attemptId) async {
    attempts.removeWhere((attempt) => attempt.id == attemptId);
  }
}

void main() {
  late _MemoryAttemptStore store;
  late AttemptController controller;
  late _IdleTelemetry source;

  setUp(() {
    store = _MemoryAttemptStore();
    source = _IdleTelemetry();
    controller = AttemptController(
      source,
      store,
      const AttemptComparisonService(),
    );
  });
  tearDown(() {
    controller.dispose();
    source.dispose();
  });

  Attempt savedAttempt(AttemptScenario scenario, int minute) {
    final startedAt = DateTime.utc(2026, 10, 7, 12, minute);
    final attempt = Attempt(
      id: store.attempts.length + 1,
      scenario: scenario,
      sequenceNumber:
          store.attempts.where((a) => a.scenario == scenario).length + 1,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(seconds: 2)),
      status: AttemptStatus.completed,
      sampleCount: 1,
    );
    store.attempts.add(attempt);
    return attempt;
  }

  Future<void> mount(WidgetTester tester) async {
    await controller.initialize();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: Scaffold(body: AttemptsSection())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder compareButton() =>
      find.widgetWithText(ElevatedButton, 'Compare attempts');

  testWidgets('groups saved attempts by scenario', (tester) async {
    savedAttempt(AttemptScenario.withoutFiltration, 1);
    savedAttempt(AttemptScenario.withFiltration, 2);
    await mount(tester);

    expect(find.text('Without filtration'), findsOneWidget);
    expect(find.text('With filtration'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Without filtration')).dy,
      lessThan(tester.getTopLeft(find.text('Without filtration #1')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Without filtration #1')).dy,
      lessThan(tester.getTopLeft(find.text('With filtration')).dy),
    );
    expect(
      tester.getTopLeft(find.text('With filtration')).dy,
      lessThan(tester.getTopLeft(find.text('With filtration #1')).dy),
    );
  });

  testWidgets('keeps the last instruction above the bottom navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(450, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (var minute = 1; minute <= 4; minute++) {
      savedAttempt(AttemptScenario.withoutFiltration, minute);
      savedAttempt(AttemptScenario.withFiltration, minute + 4);
    }
    await controller.initialize();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(
            extendBody: true,
            body: AttemptsSection(),
            bottomNavigationBar: SizedBox(
              height: 100,
              child: Text('Navigation'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(
      tester
          .getBottomLeft(
            find.text(
              'Select one saved attempt from each scenario before comparing.',
            ),
          )
          .dy,
      lessThan(tester.getTopLeft(find.text('Navigation')).dy),
    );
  });

  testWidgets(
    'enables Compare only after one attempt from each group is selected',
    (tester) async {
      savedAttempt(AttemptScenario.withoutFiltration, 1);
      savedAttempt(AttemptScenario.withoutFiltration, 2);
      savedAttempt(AttemptScenario.withFiltration, 3);
      await mount(tester);

      expect(tester.widget<ElevatedButton>(compareButton()).onPressed, isNull);
      await tester.tap(find.text('Without filtration #1'));
      await tester.pump();
      expect(tester.widget<ElevatedButton>(compareButton()).onPressed, isNull);
      await tester.tap(find.text('Without filtration #2'));
      await tester.pump();
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'Without filtration #1'),
            )
            .selected,
        isFalse,
      );
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'Without filtration #2'),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.text('With filtration #1'));
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(compareButton()).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'requires confirmation before deleting and clears a deleted selection',
    (tester) async {
      final without = savedAttempt(AttemptScenario.withoutFiltration, 1);
      savedAttempt(AttemptScenario.withFiltration, 2);
      await mount(tester);
      await tester.tap(find.text('Without filtration #1'));
      await tester.tap(find.text('With filtration #1'));
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(compareButton()).onPressed,
        isNotNull,
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Without filtration #1'),
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(store.attempts.map((a) => a.id), contains(without.id));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.attempts.map((a) => a.id), contains(without.id));
      expect(
        tester.widget<ElevatedButton>(compareButton()).onPressed,
        isNotNull,
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Without filtration #1'),
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(store.attempts.map((a) => a.id), isNot(contains(without.id)));
      expect(find.text('Without filtration #1'), findsNothing);
      expect(tester.widget<ElevatedButton>(compareButton()).onPressed, isNull);
    },
  );
}
