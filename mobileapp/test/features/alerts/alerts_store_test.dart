import 'dart:io';

import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('migrates a legacy gas activation without inserting an alert', () async {
    final directory = await Directory.systemTemp.createTemp('alerts-store-');
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/biomass_iot.db',
    );
    final store = AlertsStore(database);
    await store.setAlertState('gas_hazard', true);

    await store.migrateLegacyGasHazard();

    expect(await store.getActiveAlertStates(), {'trigger:high_mq2_gas'});
    expect(await store.getAlertCount(), 0);
    await database.close();
    await directory.delete(recursive: true);
  });
}
