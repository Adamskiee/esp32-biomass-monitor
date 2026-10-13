import 'dart:io';

import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/alerts/alert_item.dart';
import 'package:biomass_iot_app/features/alerts/alerts_controller.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

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
}
