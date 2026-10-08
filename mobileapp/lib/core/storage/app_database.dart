import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({DatabaseFactory? databaseFactory, String? databasePath})
    : _databaseFactory = databaseFactory ?? _defaultDatabaseFactory,
      _databasePath = databasePath;

  static final DatabaseFactory _defaultDatabaseFactory = databaseFactory;
  final DatabaseFactory _databaseFactory;
  final String? _databasePath;
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (kIsWeb) throw UnsupportedError('SQLite is not supported on the Web');
    _database = await _databaseFactory.openDatabase(
      _databasePath ?? await _defaultPath(),
      options: OpenDatabaseOptions(
        version: 3,
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
}
