import 'dart:io';

import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/alerts/alert_item.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_history_store.dart';
import 'package:biomass_iot_app/features/safety/audit_log.dart';
import 'package:biomass_iot_app/features/safety/audit_log_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('biomass-db-');
    databasePath = '${temporaryDirectory.path}/biomass_iot.db';
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('preserves version two rows after reopening the database', () async {
    final firstDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final history = SensorHistoryStore(firstDatabase);
    final alerts = AlertsStore(firstDatabase);
    final auditLogs = AuditLogStore(firstDatabase);
    final timestamp = DateTime.utc(2026, 10, 6, 12);

    await history.insertSensorData(
      SensorData(
        temperatureC: 28.5,
        chamberTempC: 36.5,
        mq135V: 1.2,
        mq2V: 2.3,
        timestamp: timestamp,
      ),
    );
    await alerts.insertAlert(
      AlertItem(
        id: 'alert-1',
        title: 'Gas detected',
        description: 'MQ2 is high',
        severity: 'critical',
        timestamp: timestamp,
      ),
    );
    await auditLogs.insertAuditLog(
      AuditLog('Enabled sprinkler', 'admin', '12:00'),
    );
    expect(
      (await firstDatabase.database).rawQuery('PRAGMA user_version'),
      completion(contains(isNotEmpty)),
    );
    await firstDatabase.close();

    final reopenedDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final reopenedHistory = SensorHistoryStore(reopenedDatabase);
    final reopenedAlerts = AlertsStore(reopenedDatabase);
    final reopenedAuditLogs = AuditLogStore(reopenedDatabase);

    final version = await (await reopenedDatabase.database).rawQuery(
      'PRAGMA user_version',
    );
    expect(version.single['user_version'], 2);
    expect((await reopenedHistory.getSensorData()).single.chamberTempC, 36.5);
    expect((await reopenedAlerts.getAlerts()).single.id, 'alert-1');
    expect(
      (await reopenedAuditLogs.getAuditLogs()).single.action,
      'Enabled sprinkler',
    );
    await reopenedDatabase.close();
  });
}
