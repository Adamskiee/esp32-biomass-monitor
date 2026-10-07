import 'dart:io';

import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/alerts/alerts_controller.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

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
}
