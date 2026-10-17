import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/alerts/alerts_controller.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/api_service.dart';
import 'package:biomass_iot_app/features/safety/widgets/safety_controls_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    databaseFactory = databaseFactorySqflitePlugin;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp/biomass-tests',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.tekartik.sqflite'),
      (call) async => switch (call.method) {
        'openDatabase' => {'id': 1},
        'query' =>
          (call.arguments as Map)['sql'] == 'PRAGMA user_version'
              ? [
                  {'user_version': 2},
                ]
              : <Map<String, Object?>>[],
        'insert' => 1,
        _ => null,
      },
    );
  });

  test('history loading preserves readings received while it was pending', () {
    final persisted = SensorData(
      timestamp: DateTime.utc(2026, 10, 14, 10),
      temperatureC: 25,
    );
    final live = SensorData(
      timestamp: DateTime.utc(2026, 10, 14, 11),
      temperatureC: 30,
    );

    final history = mergeSensorHistory(persisted: [persisted], live: [live]);

    expect(history.map((reading) => reading.temperatureC), [25, 30]);
  });

  test(
    'a poll from the previous device cannot update history or alerts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final response = Completer<http.Response>();
      final directory = await Directory.systemTemp.createTemp('session-poll-');
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: '${directory.path}/app.db',
      );
      final controller = AlertsController(AlertsStore(database));
      final client = MockClient((_) => response.future);
      final state = AppStateProvider(
        prefs,
        client: client,
        alertsController: controller,
      );
      final poll = state.pollOnce();
      await state.saveDeviceIp('192.168.1.23');
      response.complete(
        http.Response(
          '{"chamber_temp_c":100,"active_triggers":["high_chamber_temp"]}',
          200,
        ),
      );
      await poll;
      expect(state.telemetryRevision, 0);
      expect(await AlertsStore(database).getAlertCount(), 0);
      state.dispose();
      controller.dispose();
      client.close();
      await database.close();
      await directory.delete(recursive: true);
    },
  );

  testWidgets(
    'panel and provider reject old recovery and persist one shared activation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final older = Completer<http.Response>();
      var requests = 0;
      final active = jsonEncode({
        'pm2_5_ug_m3': 90,
        'threshold_pm2_5_ug_m3': 60,
        'pump_on': false,
        'active_triggers': ['high_pm2_5'],
      });
      final client = MockClient((_) async {
        requests++;
        if (requests == 2) return older.future;
        return http.Response(active, 200);
      });
      late Directory directory;
      late AppDatabase database;
      late AlertsStore store;
      late AlertsController controller;
      late AppStateProvider state;
      var sounds = 0;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('shared-panel-');
        database = AppDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: '${directory.path}/app.db',
        );
        store = AlertsStore(database);
        controller = AlertsController(store);
        await controller.load();
        await controller.recordTriggers(
          SensorData(pm2_5UgM3: 90, timestamp: DateTime.now()),
          ['high_pm2_5'],
        );
        state = AppStateProvider(
          prefs,
          client: client,
          alertsController: controller,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SafetyControlsPanel(
                apiService: ApiService(
                  baseUrl: 'http://device/api',
                  authorizationHeader: 'Basic test',
                  client: client,
                ),
                observationRecorder: state.safetyObservationRecorder,
                onAlert: () => sounds++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.text('High PM2.5'), findsOneWidget);
      expect(sounds, 1);
      await tester.tap(find.byTooltip('Mute app alerts'));
      await tester.pump(const Duration(seconds: 2));
      final providerPoll = state.pollOnce();
      for (var attempt = 0; attempt < 5; attempt++) {
        await tester.pump();
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await providerPoll;
      older.complete(http.Response('{"active_triggers":[]}', 200));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.text('High PM2.5'), findsOneWidget);
      expect(find.text('No active alerts'), findsNothing);
      expect(sounds, 1);
      await tester.runAsync(() async {
        expect(await store.getAlertCount(), 1);
      });
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      controller.dispose();
      client.close();
      await tester.runAsync(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
    },
  );

  for (final olderFails in [false, true]) {
    test(
      'older poll cannot overwrite accepted telemetry, failure=$olderFails',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final older = Completer<http.Response>();
        final newer = Completer<http.Response>();
        var requests = 0;
        final client = MockClient(
          (_) => ++requests == 1 ? older.future : newer.future,
        );
        final directory = await Directory.systemTemp.createTemp(
          'ordered-provider-',
        );
        final database = AppDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: '${directory.path}/app.db',
        );
        final controller = AlertsController(AlertsStore(database));
        final state = AppStateProvider(
          prefs,
          client: client,
          alertsController: controller,
        );
        await state.saveDeviceIp('127.0.0.1');
        final first = state.pollOnce();
        final second = state.pollOnce();
        newer.complete(
          http.Response(
            '{"chamber_temp_c":90,"active_triggers":["high_chamber_temp"]}',
            200,
          ),
        );
        await second;
        older.complete(
          olderFails
              ? http.Response('Offline', 503)
              : http.Response(
                  '{"chamber_temp_c":40,"active_triggers":[]}',
                  200,
                ),
        );
        await first;
        expect(state.isHardwareConnected, isTrue);
        expect(state.currentData.chamberTempC, 90);
        expect(
          state.history.where((reading) => reading.chamberTempC == 40),
          isEmpty,
        );
        expect(state.telemetryRevision, 1);
        expect(await AlertsStore(database).getAlertCount(), 1);
        state.dispose();
        controller.dispose();
        client.close();
        await database.close();
        await directory.delete(recursive: true);
      },
    );
  }

  test(
    'login accepts device credentials and uses the saved device IP',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{}',
          request.headers['Authorization'] ==
                  'Basic ${base64Encode(utf8.encode('operator:secret'))}'
              ? 200
              : 401,
        );
      });
      final state = AppStateProvider(prefs, client: client);
      await state.saveDeviceIp('192.168.1.42');

      expect(await state.login('operator', 'wrong'), isFalse);
      expect(state.isAuthenticated, isFalse);
      expect(await state.login('operator', 'secret'), isTrue);
      expect(state.isAuthenticated, isTrue);
      expect(requests.last.url.host, '192.168.1.42');

      state.dispose();
      client.close();
    },
  );

  test('offline polls do not create sensor history', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var online = true;
    final client = MockClient(
      (request) async =>
          http.Response(online ? '{}' : 'Unavailable', online ? 200 : 503),
    );
    final state = AppStateProvider(prefs, client: client);
    await state.saveDeviceIp('192.168.1.42');
    expect(await state.login('operator', 'secret'), isTrue);
    online = false;

    await state.pollOnce();
    expect(state.isHardwareConnected, isFalse);
    expect(state.currentData.chamberTempC, isNull);
    expect(state.history, isEmpty);

    state.dispose();
    client.close();
  });

  test(
    'live telemetry records sensor faults in the shared alerts state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final client = MockClient(
        (_) async => http.Response('''{
          "temperature_c": null,
          "humidity_percent": null,
          "chamber_temp_c": null,
          "mq135_v": null,
          "mq2_v": null,
          "pm1_0_ug_m3": null,
          "pm2_5_ug_m3": null,
          "pm10_ug_m3": null,
          "active_triggers": ["temp_sensor_fault", "mq2_sensor_fault"]
        }''', 200),
      );
      final directory = await Directory.systemTemp.createTemp(
        'app-state-alerts-',
      );
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: '${directory.path}/biomass_iot.db',
      );
      final state = AppStateProvider(
        prefs,
        client: client,
        alertsController: AlertsController(AlertsStore(database)),
      );
      await state.saveDeviceIp('192.168.1.42');
      expect(await state.login('operator', 'secret'), isTrue);
      state.logout();

      await state.pollOnce();

      expect(state.alertCount, 5);

      state.dispose();
      client.close();
      await database.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'session analytics includes ambient, MQ135, and particulate values',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'temperature_c': 30.0,
            'chamber_temp_c': 60.0,
            'mq135_v': 0.75,
            'mq2_v': 1.25,
            'pm1_0_ug_m3': 8.0,
            'pm2_5_ug_m3': 12.0,
            'pm10_ug_m3': 18.0,
          }),
          200,
        ),
      );
      final directory = await Directory.systemTemp.createTemp(
        'app-state-analytics-',
      );
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: '${directory.path}/biomass_iot.db',
      );
      final state = AppStateProvider(
        prefs,
        client: client,
        alertsController: AlertsController(AlertsStore(database)),
      );
      await state.saveDeviceIp('192.168.1.42');
      expect(await state.login('operator', 'secret'), isTrue);

      await state.pollOnce();

      expect(
        state.getSessionAnalytics(),
        containsPair('avgAmbientTemp', '30.0'),
      );
      expect(state.getSessionAnalytics(), containsPair('avgMq135', '0.75'));
      expect(state.getSessionAnalytics(), containsPair('avgPm2_5', '12.0'));

      state.dispose();
      client.close();
      await database.close();
      await directory.delete(recursive: true);
    },
  );
}
