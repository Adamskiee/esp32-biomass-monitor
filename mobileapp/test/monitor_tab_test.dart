import 'dart:async';

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
    Future<Uri?> Function(List<SensorData>)? csvSaver,
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
          home: MonitorTab(
            sensorLogController: logController,
            csvSaver: csvSaver,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> download(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.byTooltip('Save CSV'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save CSV'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens Save As directly with a snapshot of session readings', (
    tester,
  ) async {
    final pending = Completer<Uri?>();
    List<SensorData>? saved;
    await mount(
      tester,
      csvSaver: (records) {
        saved = records;
        return pending.future;
      },
    );
    final reading = SensorData(
      temperatureC: 31.2,
      timestamp: DateTime.utc(2026, 10, 19),
    );
    state.history.add(reading);
    await download(tester);
    expect(saved, [reading]);
    state.history.clear();
    expect(saved, [reading]);
    expect(find.text('Export Telemetry Data'), findsNothing);
    expect(find.text('GENERATE & SHARE CSV'), findsNothing);
    expect(find.text('CSV saved successfully.'), findsNothing);
    pending.complete(Uri.parse('content://documents/chosen.csv'));
    await tester.pumpAndSettle();
    expect(find.text('CSV saved successfully.'), findsOneWidget);
  });

  testWidgets('does not open Save As without readings', (tester) async {
    var calls = 0;
    await mount(
      tester,
      csvSaver: (_) async {
        calls++;
        return null;
      },
    );
    await download(tester);
    expect(calls, 0);
    expect(find.text('No sensor readings to save yet.'), findsOneWidget);
  });

  testWidgets('cancels silently and allows another save', (tester) async {
    var calls = 0;
    await mount(
      tester,
      csvSaver: (_) async {
        calls++;
        return null;
      },
    );
    state.history.add(SensorData(timestamp: DateTime.utc(2026, 10, 19)));
    await download(tester);
    expect(find.byType(SnackBar), findsNothing);
    await download(tester);
    expect(calls, 2);
  });

  testWidgets('reports a failed save and allows retry', (tester) async {
    var calls = 0;
    await mount(
      tester,
      csvSaver: (_) async {
        calls++;
        if (calls == 1) throw PlatformException(code: 'save_failed');
        return null;
      },
    );
    state.history.add(SensorData(timestamp: DateTime.utc(2026, 10, 19)));
    await download(tester);
    expect(find.text('Unable to save CSV. Please try again.'), findsOneWidget);
    expect(find.text('CSV saved successfully.'), findsNothing);
    await download(tester);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prevents duplicate saves while the picker is open', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<Uri?>();
    await mount(
      tester,
      csvSaver: (_) {
        calls++;
        return pending.future;
      },
    );
    state.history.add(SensorData(timestamp: DateTime.utc(2026, 10, 19)));
    await tester.scrollUntilVisible(find.byTooltip('Save CSV'), 300);
    await tester.pumpAndSettle();
    final action = tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == 'Save CSV',
          ),
        )
        .onPressed!;
    action();
    action();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Save CSV',
            ),
          )
          .onPressed,
      isNull,
    );
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Save CSV',
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  for (final fails in [false, true]) {
    testWidgets(
      'handles leaving the monitor during a ${fails ? 'failed' : 'successful'} save',
      (tester) async {
        final pending = Completer<Uri?>();
        await mount(tester, csvSaver: (_) => pending.future);
        state.history.add(SensorData(timestamp: DateTime.utc(2026, 10, 19)));
        await download(tester);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        if (fails) {
          pending.completeError(PlatformException(code: 'save_failed'));
        } else {
          pending.complete(Uri.parse('content://documents/chosen.csv'));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [
    const Size(320, 800),
    const Size(360, 640),
    const Size(640, 360),
  ]) {
    testWidgets('keeps Save As accessible at $size', (tester) async {
      var called = false;
      await mount(
        tester,
        size: size,
        csvSaver: (_) async {
          called = true;
          return null;
        },
      );
      state.history.add(SensorData(timestamp: DateTime.utc(2026, 10, 19)));
      await download(tester);
      expect(called, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keeps Save As accessible with large text', (tester) async {
    var called = false;
    await mount(
      tester,
      size: const Size(360, 640),
      textScale: 1.6,
      csvSaver: (_) async {
        called = true;
        return null;
      },
    );
    state.history.add(SensorData(timestamp: DateTime.utc(2026, 10, 19)));
    await download(tester);
    expect(called, isTrue);
    expect(tester.takeException(), isNull);
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
    await tester.scrollUntilVisible(
      find.textContaining('Ambient Temp: 31.2 °C'),
      300,
    );
    expect(find.textContaining('Chamber Temp: 58.4 °C'), findsOneWidget);
    expect(find.textContaining('Ambient Temp: 31.2 °C'), findsOneWidget);
    expect(find.textContaining('Humidity: 54.5 %'), findsOneWidget);
    expect(find.textContaining('MQ-135: 0.75 V'), findsOneWidget);
    expect(find.textContaining('MQ-2: 1.75 V'), findsOneWidget);
    expect(find.textContaining('PM1.0: 8 µg/m³'), findsOneWidget);
    expect(find.textContaining('PM2.5: 12 µg/m³'), findsOneWidget);
    expect(find.textContaining('PM10: 18 µg/m³'), findsOneWidget);
  });

  testWidgets('opens directly to sensor records', (tester) async {
    await history.insertSensorData(
      SensorData(temperatureC: 25, timestamp: DateTime(2026, 10, 7)),
    );
    await mount(tester);
    expect(find.text('Session Analytics'), findsNothing);
    expect(find.text('Sensor Data Log').hitTestable(), findsOneWidget);
    expect(find.text('Telemetry Record').hitTestable(), findsOneWidget);
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
