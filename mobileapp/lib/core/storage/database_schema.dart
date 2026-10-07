import 'package:sqflite/sqflite.dart';

abstract final class DatabaseSchema {
  static const version = 3;

  static Future<void> configure(Database db) =>
      db.execute('PRAGMA foreign_keys = ON');

  static Future<void> create(Database db, int version) async {
    await _createSensorDataTable(db);
    await _createAlertsTable(db);
    await _createAuditLogsTable(db);
    await _createAttemptTables(db);
  }

  static Future<void> upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS sensor_data');
      await _createSensorDataTable(db);
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE sensor_data ADD COLUMN humidity_percent REAL',
      );
      await db.execute('ALTER TABLE sensor_data ADD COLUMN pm1_ug_m3 REAL');
      await db.execute('ALTER TABLE sensor_data ADD COLUMN pm25_ug_m3 REAL');
      await db.execute('ALTER TABLE sensor_data ADD COLUMN pm10_ug_m3 REAL');
      await _createAttemptTables(db);
    }
  }

  static Future<void> _createSensorDataTable(Database db) => db.execute('''
    CREATE TABLE sensor_data (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      temperature_c REAL,
      humidity_percent REAL,
      chamber_temp_c REAL,
      mq135_v REAL,
      mq2_v REAL,
      pm1_ug_m3 REAL,
      pm25_ug_m3 REAL,
      pm10_ug_m3 REAL,
      timestamp TEXT
    )
  ''');

  static Future<void> _createAlertsTable(Database db) => db.execute('''
    CREATE TABLE alerts (
      id TEXT PRIMARY KEY,
      title TEXT,
      description TEXT,
      severity TEXT,
      time TEXT
    )
  ''');

  static Future<void> _createAuditLogsTable(Database db) => db.execute('''
    CREATE TABLE audit_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      action TEXT,
      user TEXT,
      timestamp TEXT
    )
  ''');

  static Future<void> _createAttemptTables(Database db) async {
    await db.execute('''
      CREATE TABLE attempts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scenario TEXT NOT NULL,
        sequence_number INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        status TEXT NOT NULL,
        UNIQUE(scenario, sequence_number)
      )
    ''');
    await db.execute('''
      CREATE TABLE attempt_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        attempt_id INTEGER NOT NULL REFERENCES attempts(id) ON DELETE CASCADE,
        recorded_at TEXT NOT NULL,
        elapsed_ms INTEGER NOT NULL,
        temperature_c REAL,
        humidity_percent REAL,
        mq135_v REAL,
        mq2_v REAL,
        pm1_ug_m3 REAL,
        pm25_ug_m3 REAL,
        pm10_ug_m3 REAL
      )
    ''');
    await db.execute(
      'CREATE INDEX attempt_readings_attempt_elapsed ON attempt_readings(attempt_id, elapsed_ms)',
    );
    await db.execute(
      "CREATE UNIQUE INDEX one_active_attempt ON attempts(status) WHERE status = 'active'",
    );
  }
}
