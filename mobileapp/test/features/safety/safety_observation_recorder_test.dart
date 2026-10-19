import 'dart:io';

import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/alerts/alerts_controller.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:biomass_iot_app/features/safety/safety_observation_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('rejects a completed older observation after a newer alert', () async {
    final directory = await Directory.systemTemp.createTemp('recorder-');
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/biomass.db',
    );
    final alerts = AlertsController(AlertsStore(database));
    final recorder = SafetyObservationRecorder(alerts);
    final older = recorder.begin();
    final newer = recorder.begin();

    expect(
      await recorder.accept(newer, {
        'pm2_5_ug_m3': 90,
        'active_triggers': ['high_pm2_5'],
      }),
      isTrue,
    );
    expect(await recorder.accept(older, {'active_triggers': []}), isFalse);
    expect(await AlertsStore(database).getAlertCount(), 1);
    await database.close();
    await directory.delete(recursive: true);
  });
}
