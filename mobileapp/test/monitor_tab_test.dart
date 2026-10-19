import 'dart:async';
import 'dart:io';

import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/features/monitoring/monitor_tab.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_history_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_log_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: MonitorTab(sensorLogController: logController),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> openExport(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.byTooltip('Export CSV'), 300);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Export CSV'));
    await tester.pumpAndSettle();
  }

  Future<Completer<MethodCall>> prepareShare(
    WidgetTester tester, {
    bool fail = false,
  }) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('telemetry-export-test-'),
    ))!;
    final called = (await tester.runAsync(
      () async => Completer<MethodCall>(),
    ))!;
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, (call) async {
      expect(call.method, 'getTemporaryDirectory');
      return directory.path;
    });
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      called.complete(call);
      if (fail) throw PlatformException(code: 'share_failed');
      return 'android.share.target';
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(shareChannel, null);
      messenger.setMockMethodCallHandler(pathChannel, null);
      await directory.delete(recursive: true);
    });
    return called;
  }

  testWidgets('shares a named CSV attachment containing session readings', (
    tester,
  ) async {
    final shared = await prepareShare(tester);
    await mount(tester);
    state.history.add(
      SensorData(
        temperatureC: 31.2,
        humidityPercent: 54.5,
        timestamp: DateTime.utc(2026, 10, 19, 12),
      ),
    );
    await openExport(tester);
    final call = (await tester.runAsync(() async {
      // File IO must start outside the widget test's fake async zone.
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'GENERATE & SHARE CSV'),
          )
          .onPressed!();
      return shared.future.timeout(const Duration(seconds: 5));
    }))!;
    await tester.pumpAndSettle();

    expect(call.method, 'share');
    final arguments = call.arguments as Map;
    expect(arguments['text'], isNull);
    expect(arguments['mimeTypes'], ['text/csv']);
    final paths = arguments['paths'] as List;
    expect(paths, hasLength(1));
    final file = File(paths.single as String);
    expect(file.uri.pathSegments.last, 'Biomass_Telemetry_Export.csv');
    final contents = await tester.runAsync(file.readAsString);
    expect(
      contents,
      'Timestamp,Temperature(C),Humidity(%),ChamberTemperature(C),MQ135(V),MQ2(V),PM1.0(ug/m3),PM2.5(ug/m3),PM10(ug/m3)\n'
      '2026-10-19T12:00:00.000Z,31.20,54.50,,,,,,\n',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains when there are no session readings to export', (
    tester,
  ) async {
    await mount(tester);
    await openExport(tester);
    await tester.tap(find.text('GENERATE & SHARE CSV'));
    await tester.pumpAndSettle();

    expect(find.text('No sensor readings to export yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows feedback when Android sharing fails', (tester) async {
    final shared = await prepareShare(tester, fail: true);
    await mount(tester);
    state.history.add(SensorData(timestamp: DateTime.utc(2026, 10, 19)));
    await openExport(tester);
    await tester.runAsync(() async {
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'GENERATE & SHARE CSV'),
          )
          .onPressed!();
      await shared.future.timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to export CSV. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 800),
    const Size(360, 640),
    const Size(640, 360),
  ]) {
    testWidgets('opens the CSV export sheet at $size', (tester) async {
      await mount(tester, size: size);
      await openExport(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Export Telemetry Data'), findsOneWidget);
      final generate = find.text('GENERATE & SHARE CSV');
      await tester.ensureVisible(generate);
      expect(generate.hitTestable(), findsOneWidget);
    });
  }

  testWidgets('keeps CSV export accessible with large text', (tester) async {
    await mount(tester, size: const Size(360, 640), textScale: 1.6);
    await openExport(tester);

    expect(tester.takeException(), isNull);
    final generate = find.text('GENERATE & SHARE CSV');
    await tester.ensureVisible(generate);
    expect(generate.hitTestable(), findsOneWidget);
  });

  testWidgets(
    'keeps the timestamp clear of sensor readings on narrow screens',
    (tester) async {
      await history.insertSensorData(
        SensorData(
          chamberTempC: 58.4,
          mq2V: 1.75,
          pm1_0UgM3: 8,
          pm2_5UgM3: 12,
          pm10UgM3: 18,
          temperatureC: 31.2,
          timestamp: DateTime(2026, 10, 7, 12, 34, 56),
        ),
      );

      await mount(tester, size: const Size(320, 800));

      await tester.scrollUntilVisible(find.text('12:34:56'), 300);
      expect(tester.takeException(), isNull);
      expect(find.text('12:34:56'), findsOneWidget);
    },
  );

  testWidgets('lists every sensor reading without an air quality segment', (
    tester,
  ) async {
    await history.insertSensorData(
      SensorData(
        chamberTempC: 58.4,
        temperatureC: 31.2,
        humidityPercent: 54.5,
        mq135V: 0.75,
        mq2V: 1.75,
        pm1_0UgM3: 8,
        pm2_5UgM3: 12,
        pm10UgM3: 18,
        timestamp: DateTime(2026, 10, 7, 12, 34, 56),
      ),
    );

    await mount(tester);

    expect(find.text('Air Quality'), findsNothing);
    expect(find.text('Ambient Temperature'), findsOneWidget);
    expect(find.text('PM2.5'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Ambient Temp: 31.2 °C'),
      300,
    );
    expect(find.textContaining('Ambient Temp: 31.2 °C'), findsOneWidget);
    expect(find.textContaining('Humidity: 54.5 %'), findsOneWidget);
    expect(find.textContaining('MQ-135: 0.75 V'), findsOneWidget);
    expect(find.textContaining('PM1.0: 8 µg/m³'), findsOneWidget);
  });

  testWidgets('groups session analytics by sensor type', (tester) async {
    await mount(tester);

    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Gas Sensors'), findsOneWidget);
    expect(find.text('Particulate Matter'), findsOneWidget);
    expect(find.text('Chamber Temperature'), findsOneWidget);
    expect(find.text('Ambient Temperature'), findsOneWidget);
    expect(find.text('Humidity'), findsOneWidget);
    expect(find.text('Peak'), findsNWidgets(8));
    expect(find.text('Average'), findsNWidgets(8));
  });

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
