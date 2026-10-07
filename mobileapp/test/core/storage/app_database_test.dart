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

  test('migrates version two rows without data loss', () async {
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE sensor_data (id INTEGER PRIMARY KEY AUTOINCREMENT, temperature_c REAL, chamber_temp_c REAL, mq135_v REAL, mq2_v REAL, timestamp TEXT)',
          );
          await db.execute(
            'CREATE TABLE alerts (id TEXT PRIMARY KEY, title TEXT, description TEXT, severity TEXT, time TEXT)',
          );
          await db.execute(
            'CREATE TABLE audit_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, action TEXT, user TEXT, timestamp TEXT)',
          );
        },
      ),
    );
    final timestamp = DateTime.utc(2026, 10, 6, 12);
    await legacy.insert('sensor_data', {
      'temperature_c': 28.5,
      'chamber_temp_c': 36.5,
      'mq135_v': 1.2,
      'mq2_v': 2.3,
      'timestamp': timestamp.toIso8601String(),
    });
    await legacy.insert('alerts', {
      'id': 'alert-1',
      'title': 'Gas detected',
      'description': 'MQ2 is high',
      'severity': 'critical',
      'time': timestamp.toIso8601String(),
    });
    await legacy.insert('audit_logs', {
      'action': 'Enabled sprinkler',
      'user': 'admin',
      'timestamp': '12:00',
    });
    await legacy.close();

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
    expect((await reopenedAlerts.getAlerts()).single.id, 'alert-1');
    expect(
      (await reopenedAuditLogs.getAuditLogs()).single.action,
      'Enabled sprinkler',
    );
    final columns = await (await reopenedDatabase.database).rawQuery(
      'PRAGMA table_info(sensor_data)',
    );
    expect(
      columns.map((column) => column['name']),
      containsAll([
        'humidity_percent',
        'pm1_ug_m3',
        'pm25_ug_m3',
        'pm10_ug_m3',
      ]),
    );
    final tables = await (await reopenedDatabase.database).rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(
      tables.map((table) => table['name']),
      containsAll(['attempts', 'attempt_readings']),
    );
    final foreignKeys = await (await reopenedDatabase.database).rawQuery(
      'PRAGMA foreign_keys',
    );
    expect(foreignKeys.single['foreign_keys'], 1);
    await reopenedDatabase.close();
  });
}
