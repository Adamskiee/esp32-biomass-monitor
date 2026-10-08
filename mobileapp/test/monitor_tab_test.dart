import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/features/monitoring/monitor_tab.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_history_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_log_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySensorHistoryStore implements SensorHistoryReader {
  final List<SensorData> _records = [];

  Future<int> insertSensorData(SensorData data) async {
    _records.add(data);
    return _records.length;
  }

  @override
  Future<int> getLatestSensorDataId() async => _records.length;

  @override
  Future<int> getSensorDataCount({int? throughId}) async =>
      throughId ?? _records.length;

  @override
  Future<List<SensorData>> getSensorData({
    int limit = 100,
    int offset = 0,
    int? throughId,
  }) async {
    final end = throughId ?? _records.length;
    return _records
        .take(end)
        .toList()
        .reversed
        .skip(offset)
        .take(limit)
        .toList();
  }
}

class _FailingSensorHistoryReader implements SensorHistoryReader {
  @override
  Future<int> getLatestSensorDataId() async => throw StateError('unavailable');

  @override
  Future<int> getSensorDataCount({int? throughId}) async =>
      throw StateError('unavailable');

  @override
  Future<List<SensorData>> getSensorData({
    int limit = 100,
    int offset = 0,
    int? throughId,
  }) async => throw StateError('unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemorySensorHistoryStore history;
  late SensorLogController logController;
  late AppStateProvider state;

  setUp(() async {
    history = _MemorySensorHistoryStore();
    logController = SensorLogController(history);
    SharedPreferences.setMockInitialValues({});
    state = AppStateProvider(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    state.dispose();
    logController.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(450, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          home: MonitorTab(sensorLogController: logController),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'keeps the timestamp clear of sensor readings on narrow screens',
    (tester) async {
      await history.insertSensorData(
        SensorData(
          chamberTempC: 58.4,
          mq2V: 1.75,
          temperatureC: 31.2,
          timestamp: DateTime(2026, 10, 7, 12, 34, 56),
        ),
      );

      await mount(tester, size: const Size(320, 800));

      expect(tester.takeException(), isNull);
      expect(find.text('12:34:56'), findsOneWidget);
    },
  );

  testWidgets('shows ten records per page with navigation controls', (
    tester,
  ) async {
    final start = DateTime(2026, 10, 7, 12);
    for (var index = 0; index < 25; index++) {
      await history.insertSensorData(
        SensorData(
          temperatureC: index.toDouble(),
          timestamp: start.add(Duration(minutes: index)),
        ),
      );
    }

    await mount(tester);

    expect(logController.records, hasLength(10));
    expect(logController.records.first.temperatureC, 24);
    await tester.scrollUntilVisible(find.text('Live updates'), 300);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.scrollUntilVisible(find.text('Next'), 300);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(logController.records, hasLength(10));
    expect(logController.records.first.temperatureC, 14);
  });

  testWidgets('shows a retry action when sensor history cannot load', (
    tester,
  ) async {
    logController.dispose();
    logController = SensorLogController(_FailingSensorHistoryReader());

    await mount(tester);
    await tester.scrollUntilVisible(
      find.text('Unable to load sensor data. Try again.'),
      300,
    );

    expect(find.text('Unable to load sensor data. Try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
