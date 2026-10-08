import 'dart:io';

import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/database_helper.dart';
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

  test('preserves rows after reopening the database', () async {
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
    expect(version.single['user_version'], 3);
    expect((await reopenedHistory.getSensorData()).single.chamberTempC, 36.5);
    expect((await reopenedHistory.getSensorData()).single.pm1_0UgM3, isNull);
    expect((await reopenedAlerts.getAlerts()).single.id, 'alert-1');
    expect(
      (await reopenedAuditLogs.getAuditLogs()).single.action,
      'Enabled sprinkler',
    );
    await reopenedDatabase.close();
  });

  test('migrates version two rows through each history API', () async {
    Future<void> seedVersionTwo(String path) async {
      final database = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE sensor_data (id INTEGER PRIMARY KEY AUTOINCREMENT, temperature_c REAL, chamber_temp_c REAL, mq135_v REAL, mq2_v REAL, timestamp TEXT)');
            await db.execute('CREATE TABLE alerts (id TEXT PRIMARY KEY, title TEXT, description TEXT, severity TEXT, time TEXT)');
            await db.execute('CREATE TABLE audit_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, action TEXT, user TEXT, timestamp TEXT)');
          },
        ),
      );
      await database.insert('sensor_data', {'temperature_c': 25.0, 'timestamp': DateTime.utc(2026, 10, 8).toIso8601String()});
      await database.insert('alerts', {'id': 'old-alert', 'title': 'Old', 'description': 'Saved', 'severity': 'info', 'time': DateTime.utc(2026, 10, 8).toIso8601String()});
      await database.insert('audit_logs', {'action': 'Old action', 'user': 'admin', 'timestamp': '08:00'});
      await database.close();
    }

    final appPath = '${temporaryDirectory.path}/app.db';
    await seedVersionTwo(appPath);
    final appDatabase = AppDatabase(databaseFactory: databaseFactoryFfi, databasePath: appPath);
    final appHistory = SensorHistoryStore(appDatabase);
    expect(await (await appDatabase.database).getVersion(), 3);
    expect((await appHistory.getSensorData()).single.pm2_5UgM3, isNull);
    expect((await AlertsStore(appDatabase).getAlerts()).single.id, 'old-alert');
    expect((await AuditLogStore(appDatabase).getAuditLogs()).single.action, 'Old action');
    await appHistory.insertSensorData(SensorData(pm1_0UgM3: 8, pm2_5UgM3: 12, pm10UgM3: 18, timestamp: DateTime.utc(2026, 10, 8, 1)));
    expect((await appHistory.getSensorData()).first.pm10UgM3, 18.0);
    await appHistory.insertSensorData(
      SensorData(timestamp: DateTime.now().subtract(const Duration(minutes: 1))),
    );
    await appHistory.insertSensorData(
      SensorData(pm2_5UgM3: 12, timestamp: DateTime.now()),
    );
    expect((await appHistory.getAggregatedSensorData(1)).last.pm2_5UgM3, 12.0);
    await appDatabase.close();

    final legacyPath = '${temporaryDirectory.path}/legacy.db';
    await seedVersionTwo(legacyPath);
    final legacyStorage = AppDatabase(databaseFactory: databaseFactoryFfi, databasePath: legacyPath);
    final legacyHistory = DatabaseHelper.forTesting(legacyStorage);
    expect(await (await legacyStorage.database).getVersion(), 3);
    expect((await legacyHistory.getSensorData()).single.pm1_0UgM3, isNull);
    await legacyHistory.insertSensorData(SensorData(pm1_0UgM3: 8, pm2_5UgM3: 12, pm10UgM3: 18, timestamp: DateTime.utc(2026, 10, 8, 2)));
    expect((await legacyHistory.getSensorData()).first.pm2_5UgM3, 12.0);
    await legacyStorage.close();
  });

  test('reads a stable sensor history page with its total count', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final history = SensorHistoryStore(database);
    final start = DateTime.utc(2026, 10, 7, 12);

    expect(await history.getLatestSensorDataId(), 0);

    for (var index = 0; index < 25; index++) {
      await history.insertSensorData(
        SensorData(
          temperatureC: index.toDouble(),
          timestamp: start.add(Duration(minutes: index)),
        ),
      );
    }

    final snapshotId = await history.getLatestSensorDataId();
    final page = await history.getSensorData(
      limit: 10,
      offset: 10,
      throughId: snapshotId,
    );

    expect(snapshotId, 25);
    expect(await history.getSensorDataCount(throughId: snapshotId), 25);
    expect(page, hasLength(10));
    expect(page.first.temperatureC, 14);
    expect(page.last.temperatureC, 5);

    await history.insertSensorData(
      SensorData(
        temperatureC: 99,
        timestamp: start.add(const Duration(days: 1)),
      ),
    );

    expect(await history.getSensorDataCount(throughId: snapshotId), 25);
    expect(
      (await history.getSensorData(
        limit: 10,
        throughId: snapshotId,
      )).first.temperatureC,
      24,
    );
    await database.close();
  });
}
