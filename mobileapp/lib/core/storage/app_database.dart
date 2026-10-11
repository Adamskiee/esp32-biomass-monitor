import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database_provider.dart';

class AppDatabase implements DatabaseProvider {
  AppDatabase({DatabaseFactory? databaseFactory, String? databasePath})
    : _databaseFactory = databaseFactory ?? _defaultDatabaseFactory,
      _databasePath = databasePath;

  static final DatabaseFactory _defaultDatabaseFactory = databaseFactory;
  final DatabaseFactory _databaseFactory;
  final String? _databasePath;
  Database? _database;

  @override
  Future<Database> get database async {
    if (_database != null) return _database!;
    if (kIsWeb) throw UnsupportedError('SQLite is not supported on the Web');
    _database = await _databaseFactory.openDatabase(
      _databasePath ?? await _defaultPath(),
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return _database!;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<String> _defaultPath() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return join(documentsDirectory.path, 'biomass_iot.db');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS sensor_data');
      await _createSensorDataTable(db);
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE sensor_data ADD COLUMN pm1_0_ug_m3 REAL');
      await db.execute('ALTER TABLE sensor_data ADD COLUMN pm2_5_ug_m3 REAL');
      await db.execute('ALTER TABLE sensor_data ADD COLUMN pm10_ug_m3 REAL');
    }
    if (oldVersion < 4) await _createAttemptTables(db);
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createSensorDataTable(db);
    await db.execute('''
      CREATE TABLE alerts (
        id TEXT PRIMARY KEY,
        title TEXT,
        description TEXT,
        severity TEXT,
        time TEXT
      )
    ''');
    await _createAttemptTables(db);
    await db.execute('''
      CREATE TABLE audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT,
        user TEXT,
        timestamp TEXT
      )
    ''');
  }

  Future<void> _createSensorDataTable(Database db) => db.execute('''
    CREATE TABLE sensor_data (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      temperature_c REAL,
      chamber_temp_c REAL,
      mq135_v REAL,
      mq2_v REAL,
      pm1_0_ug_m3 REAL,
      pm2_5_ug_m3 REAL,
      pm10_ug_m3 REAL,
      timestamp TEXT
    )
  ''');

  Future<void> _createAttemptTables(Database db) async {
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
