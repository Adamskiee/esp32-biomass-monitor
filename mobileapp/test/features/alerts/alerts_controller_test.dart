import 'dart:io';

import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/alerts/alert_item.dart';
import 'package:biomass_iot_app/features/alerts/alerts_controller.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/safety/safety_condition.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('persistent safety transitions', () {
    late Directory directory;
    late AppDatabase database;
    late AlertsStore store;
    late AlertsController controller;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('safety-transitions-');
      database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: '${directory.path}/app.db',
      );
      store = AlertsStore(database);
      await database.database;
      controller = AlertsController(store);
    });
    tearDown(() async {
      controller.dispose();
      await database.close();
      await directory.delete(recursive: true);
    });

    for (final trigger in [
      'high_chamber_temp',
      'catastrophic_latch',
      'high_mq2_gas',
      'high_mq135_gas',
      'high_ambient_temp',
      'high_pm1_0',
      'high_pm2_5',
      'high_pm10',
      'low_humidity',
      'high_humidity',
    ]) {
      test(
        '$trigger survives repeats, concurrency, restart, recovery, and retrigger',
        () async {
          final reading = SensorData(timestamp: DateTime.now());
          await Future.wait([
            controller.recordTriggers(reading, [trigger]),
            controller.recordTriggers(reading, [trigger]),
          ]);
          final restarted = AlertsController(store);
          await restarted.recordTriggers(reading, [trigger]);
          expect(await store.getAlertCount(), 1);
          await restarted.recordTriggers(reading, []);
          await restarted.recordTriggers(reading, [trigger]);
          expect(await store.getAlertCount(), 2);
          restarted.dispose();
        },
      );
    }

    for (final trigger in ['high_pm2_5', 'pms_sensor_fault']) {
      test(
        'failed $trigger insertion remains retryable with no activation key',
        () async {
          final db = await database.database;
          await db.execute(
            "CREATE TEMP TRIGGER fail_alert BEFORE INSERT ON alerts BEGIN SELECT RAISE(ABORT, 'test failure'); END",
          );
          final reading = SensorData(timestamp: DateTime.now());
          await expectLater(
            controller.recordTriggers(reading, [trigger]),
            throwsA(anything),
          );
          expect(await store.getActiveAlertStates(), isEmpty);
          expect(controller.alerts, isEmpty);
          await db.execute('DROP TRIGGER fail_alert');
          await controller.recordTriggers(reading, [trigger]);
          expect(await store.getAlertCount(), 1);
        },
      );
    }

    test('failed recovery insertion keeps a fault active for retry', () async {
      final reading = SensorData(timestamp: DateTime.now());
      await controller.recordTriggers(reading, ['pms_sensor_fault']);
      final db = await database.database;
      await db.execute(
        "CREATE TEMP TRIGGER fail_alert BEFORE INSERT ON alerts BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        controller.recordTriggers(reading, []),
        throwsA(anything),
      );
      expect(await store.getActiveAlertStates(), contains('sensor:PMS5003'));
      await db.execute('DROP TRIGGER fail_alert');
      await controller.recordTriggers(reading, []);
      expect(await store.getAlertCount(), 2);
    });

    test(
      'legacy migration is atomic and does not duplicate active gas',
      () async {
        final db = await database.database;
        await store.setAlertState('gas_hazard', true);
        await db.execute(
          "CREATE TEMP TRIGGER fail_migration BEFORE INSERT ON alert_states WHEN NEW.key = 'trigger:high_mq2_gas' BEGIN SELECT RAISE(ABORT, 'test failure'); END",
        );
        await expectLater(
          controller.recordTriggers(SensorData(timestamp: DateTime.now()), [
            'high_mq2_gas',
          ]),
          throwsA(anything),
        );
        expect(await store.getActiveAlertStates(), {'gas_hazard'});
        await db.execute('DROP TRIGGER fail_migration');
        await controller.recordTriggers(SensorData(timestamp: DateTime.now()), [
          'high_mq2_gas',
        ]);
        expect(await store.getAlertCount(), 0);
        expect(await store.getActiveAlertStates(), {'trigger:high_mq2_gas'});
      },
    );

    test(
      'explicit MQ135 fault is recorded without readings and warm-up suppresses MQ conditions',
      () async {
        await controller.recordTriggers(
          SensorData.fromJson({'mq_warming_up': true}),
          [
            'mq135_sensor_fault',
            'mq2_sensor_fault',
            'high_mq2_gas',
            'high_mq135_gas',
          ],
        );
        expect(await store.getAlertCount(), 0);
        await controller.recordTriggers(SensorData(timestamp: DateTime.now()), [
          'mq135_sensor_fault',
        ]);
        expect(controller.alerts.single.title, 'WARNING: MQ135 Sensor Fault');
      },
    );

    test('unknown triggers never invent a condition', () async {
      await controller.recordTriggers(SensorData(timestamp: DateTime.now()), [
        'unknown',
      ]);
      expect(await store.getAlertCount(), 0);
    });
  });

  test('maps configured threshold triggers to readable conditions', () {
    final reading = SensorData(humidityPercent: 29, timestamp: DateTime.now());

    final lowHumidity = safetyConditionFor('low_humidity');
    final highMq2 = safetyConditionFor('high_mq2_gas');

    expect(lowHumidity, isNotNull);
    expect(lowHumidity!.title, 'Low Humidity');
    expect(lowHumidity.severity, 'warning');
    expect(lowHumidity.describe(reading), contains('29'));
    expect(highMq2!.severity, 'critical');
    expect(safetyConditionFor('unknown_trigger'), isNull);
  });

  test(
    'loads the next alert batch without changing the initial batch',
    () async {
      final directory = await Directory.systemTemp.createTemp('alerts-');
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: '${directory.path}/biomass_iot.db',
      );
      final store = AlertsStore(database);
      final timestamp = DateTime.utc(2026, 10, 13);
      for (var index = 0; index < 21; index++) {
        await store.insertAlert(
          AlertItem(
            id: 'alert-$index',
            title: 'Alert $index',
            description: 'Saved alert',
            severity: 'info',
            timestamp: timestamp.add(Duration(minutes: index)),
          ),
        );
      }
      final controller = AlertsController(store);

      await controller.load();
      expect(controller.alerts, hasLength(20));
      expect(controller.alerts.first.id, 'alert-20');
      expect(controller.hasMoreAlerts, isTrue);

      await controller.loadMore();
      expect(controller.alerts, hasLength(21));
      expect(controller.alerts.last.id, 'alert-0');
      expect(controller.hasMoreAlerts, isFalse);

      await controller.clearAllAlerts();
      expect(controller.alerts, isEmpty);
      expect(await store.getAlertCount(), 0);

      await database.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'deduplicates consecutive high MQ2 triggers in persistent alerts',
    () async {
      final directory = await Directory.systemTemp.createTemp('alerts-');
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: '${directory.path}/biomass_iot.db',
      );
      final store = AlertsStore(database);
      final controller = AlertsController(store);
      final reading = SensorData(mq2V: 2.4, timestamp: DateTime.now());

      await controller.recordTriggers(reading, ['high_mq2_gas']);
      await controller.recordTriggers(reading, ['high_mq2_gas']);

      expect(controller.alerts, hasLength(1));
      expect(await store.getAlerts(), hasLength(1));
      await database.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'records one warning per sensor fault and an info alert on recovery',
    () async {
      final directory = await Directory.systemTemp.createTemp('alerts-');
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: '${directory.path}/biomass_iot.db',
      );
      final controller = AlertsController(AlertsStore(database));
      final faultedReading = SensorData.fromJson({
        'temperature_c': null,
        'humidity_percent': null,
        'chamber_temp_c': null,
        'mq135_v': null,
        'mq2_v': null,
        'pm1_0_ug_m3': null,
        'pm2_5_ug_m3': null,
        'pm10_ug_m3': null,
      });

      await controller.recordTriggers(faultedReading, [
        'temp_sensor_fault',
        'mq2_sensor_fault',
      ]);
      await controller.recordTriggers(faultedReading, [
        'temp_sensor_fault',
        'mq2_sensor_fault',
      ]);

      expect(controller.alerts, hasLength(5));
      expect(
        controller.alerts.map((alert) => alert.title),
        containsAll(<String>[
          'WARNING: DHT22 Sensor Fault',
          'WARNING: Thermocouple Sensor Fault',
          'WARNING: MQ135 Sensor Fault',
          'WARNING: MQ2 Sensor Fault',
          'WARNING: PMS5003 Sensor Fault',
        ]),
      );
      expect(
        controller.alerts.every((alert) => alert.severity == 'warning'),
        isTrue,
      );

      await controller.recordTriggers(
        SensorData.fromJson({
          'temperature_c': 25,
          'humidity_percent': 60,
          'chamber_temp_c': 38,
          'mq135_v': 1.2,
          'mq2_v': 1.1,
          'pm1_0_ug_m3': 4,
          'pm2_5_ug_m3': 6,
          'pm10_ug_m3': 9,
        }),
        [],
      );

      expect(controller.alerts, hasLength(10));
      expect(
        controller.alerts
            .where((alert) => alert.severity == 'info')
            .map((alert) => alert.title),
        containsAll(<String>[
          'INFO: DHT22 Sensor Recovered',
          'INFO: Thermocouple Sensor Recovered',
          'INFO: MQ135 Sensor Recovered',
          'INFO: MQ2 Sensor Recovered',
          'INFO: PMS5003 Sensor Recovered',
        ]),
      );

      await database.close();
      await directory.delete(recursive: true);
    },
  );

  test('does not record MQ sensor faults while the sensors warm up', () async {
    final directory = await Directory.systemTemp.createTemp('alerts-');
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/biomass_iot.db',
    );
    final controller = AlertsController(AlertsStore(database));
    final warmupReading = SensorData.fromJson({
      'mq135_v': null,
      'mq2_v': null,
      'mq_warming_up': true,
      'mq_warmup_remaining_seconds': 300,
    });

    await controller.recordTriggers(warmupReading, []);

    expect(controller.alerts, isEmpty);
    await database.close();
    await directory.delete(recursive: true);
  });

  test('records explicit DHT22 and PMS5003 faults without readings', () async {
    final directory = await Directory.systemTemp.createTemp('alerts-');
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/biomass_iot.db',
    );
    final controller = AlertsController(AlertsStore(database));

    await controller.recordTriggers(SensorData(timestamp: DateTime.now()), [
      'ambient_temp_sensor_fault',
      'humidity_sensor_fault',
      'pms_sensor_fault',
    ]);

    expect(
      controller.alerts.where(
        (alert) => alert.title == 'WARNING: DHT22 Sensor Fault',
      ),
      hasLength(1),
    );
    expect(
      controller.alerts.where(
        (alert) => alert.title == 'WARNING: PMS5003 Sensor Fault',
      ),
      hasLength(1),
    );
    await database.close();
    await directory.delete(recursive: true);
  });

  test('retains active MQ sensor faults while the sensors warm up', () async {
    final directory = await Directory.systemTemp.createTemp('alerts-');
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/biomass_iot.db',
    );
    final controller = AlertsController(AlertsStore(database));

    await controller.recordTriggers(
      SensorData.fromJson({'mq135_v': null, 'mq2_v': null}),
      [],
    );
    await controller.recordTriggers(
      SensorData.fromJson({
        'mq135_v': null,
        'mq2_v': null,
        'mq_warming_up': true,
      }),
      [],
    );

    expect(controller.alerts, hasLength(2));
    expect(
      controller.alerts.where((alert) => alert.severity == 'info'),
      isEmpty,
    );
    await database.close();
    await directory.delete(recursive: true);
  });

  test('records MQ sensor faults after warm-up ends', () async {
    final directory = await Directory.systemTemp.createTemp('alerts-');
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/biomass_iot.db',
    );
    final controller = AlertsController(AlertsStore(database));

    await controller.recordTriggers(
      SensorData.fromJson({
        'mq135_v': null,
        'mq2_v': null,
        'mq_warming_up': true,
      }),
      [],
    );
    await controller.recordTriggers(
      SensorData.fromJson({'mq135_v': null, 'mq2_v': null}),
      [],
    );

    expect(
      controller.alerts.map((alert) => alert.title),
      containsAll(<String>[
        'WARNING: MQ135 Sensor Fault',
        'WARNING: MQ2 Sensor Fault',
      ]),
    );
    await database.close();
    await directory.delete(recursive: true);
  });

  test('records non-MQ sensor faults during MQ warm-up', () async {
    final directory = await Directory.systemTemp.createTemp('alerts-');
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/biomass_iot.db',
    );
    final controller = AlertsController(AlertsStore(database));

    await controller.recordTriggers(
      SensorData.fromJson({
        'temperature_c': null,
        'humidity_percent': null,
        'mq135_v': null,
        'mq2_v': null,
        'mq_warming_up': true,
      }),
      [],
    );

    expect(controller.alerts.map((alert) => alert.title), [
      'WARNING: DHT22 Sensor Fault',
    ]);
    await database.close();
    await directory.delete(recursive: true);
  });

  test('retains active sensor faults across a controller restart', () async {
    final directory = await Directory.systemTemp.createTemp('alerts-');
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/biomass_iot.db',
    );
    final faultedReading = SensorData.fromJson({'mq135_v': null});
    final firstController = AlertsController(AlertsStore(database));
    await firstController.recordTriggers(faultedReading, []);

    final restartedController = AlertsController(AlertsStore(database));
    await restartedController.recordTriggers(faultedReading, []);
    await restartedController.recordTriggers(
      SensorData.fromJson({'mq135_v': 1.2}),
      [],
    );

    final alerts = await AlertsStore(database).getAlerts();
    expect(alerts.where((alert) => alert.severity == 'warning'), hasLength(1));
    expect(
      alerts.where((alert) => alert.title == 'INFO: MQ135 Sensor Recovered'),
      hasLength(1),
    );

    await database.close();
    await directory.delete(recursive: true);
  });
}
