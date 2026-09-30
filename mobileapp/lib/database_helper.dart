import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'main.dart'; // To access SensorData, AlertItem, AuditLog models

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on the Web');
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'biomass_iot.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS sensor_data');
      await _createSensorDataTable(db);
    }
  }

  Future _createSensorDataTable(Database db) async {
    await db.execute('''
      CREATE TABLE sensor_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        temperature_c REAL,
        chamber_temp_c REAL,
        mq135_v REAL,
        mq2_v REAL,
        timestamp TEXT
      )
    ''');
  }

  Future _onCreate(Database db, int version) async {
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

  // --- Sensor Data CRUD ---
  Future<int> insertSensorData(SensorData data) async {
    if (kIsWeb) return 0;
    Database db = await database;
    return await db.insert('sensor_data', {
      'temperature_c': data.temperatureC,
      'chamber_temp_c': data.chamberTempC,
      'mq135_v': data.mq135V,
      'mq2_v': data.mq2V,
      'timestamp': data.timestamp.toIso8601String(),
    });
  }

  Future<List<SensorData>> getSensorData({int limit = 100}) async {
    if (kIsWeb) return [];
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'sensor_data',
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return List.generate(maps.length, (i) {
      return SensorData(
        temperatureC: maps[i]['temperature_c'] as double?,
        chamberTempC: maps[i]['chamber_temp_c'] as double?,
        mq135V: maps[i]['mq135_v'] as double?,
        mq2V: maps[i]['mq2_v'] as double?,
        timestamp: DateTime.parse(maps[i]['timestamp'] as String),
      );
    });
  }

  Future<List<SensorData>> getAggregatedSensorData(int hours) async {
    if (kIsWeb) return [];
    Database db = await database;

    // Calculate the cutoff time
    String cutoff = DateTime.now()
        .subtract(Duration(hours: hours))
        .toIso8601String();

    // Fetch all records within the timeframe
    List<Map<String, dynamic>> maps = await db.query(
      'sensor_data',
      where: 'timestamp >= ?',
      whereArgs: [cutoff],
      orderBy: 'timestamp ASC',
    );

    if (maps.isEmpty) return [];

    // Target around 60 data points for the chart
    int targetPoints = 60;
    int step = (maps.length / targetPoints).ceil();
    if (step < 1) step = 1;

    List<SensorData> aggregated = [];
    for (int i = 0; i < maps.length; i += step) {
      int end = (i + step < maps.length) ? i + step : maps.length;
      var chunk = maps.sublist(i, end);

      double sumTempC = 0, sumChamberC = 0, sumMq135 = 0, sumMq2 = 0;
      int countTempC = 0, countChamberC = 0, countMq135 = 0, countMq2 = 0;

      for (var row in chunk) {
        if (row['temperature_c'] != null) {
          sumTempC += row['temperature_c'] as double;
          countTempC++;
        }
        if (row['chamber_temp_c'] != null) {
          sumChamberC += row['chamber_temp_c'] as double;
          countChamberC++;
        }
        if (row['mq135_v'] != null) {
          sumMq135 += row['mq135_v'] as double;
          countMq135++;
        }
        if (row['mq2_v'] != null) {
          sumMq2 += row['mq2_v'] as double;
          countMq2++;
        }
      }

      aggregated.add(
        SensorData(
          temperatureC: countTempC > 0 ? sumTempC / countTempC : null,
          chamberTempC: countChamberC > 0 ? sumChamberC / countChamberC : null,
          mq135V: countMq135 > 0 ? sumMq135 / countMq135 : null,
          mq2V: countMq2 > 0 ? sumMq2 / countMq2 : null,
          timestamp: DateTime.parse(chunk.last['timestamp'] as String),
        ),
      );
    }

    return aggregated;
  }

  // --- Alerts CRUD ---
  Future<int> insertAlert(AlertItem alert) async {
    if (kIsWeb) return 0;
    Database db = await database;
    return await db.insert('alerts', {
      'id': alert.id,
      'title': alert.title,
      'description': alert.description,
      'severity': alert.severity,
      'time': alert.timestamp?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AlertItem>> getAlerts() async {
    if (kIsWeb) return [];
    Database db = await database;
    final maps = await db.query('alerts');
    final alerts = maps
        .map(
          (map) => AlertItem(
            id: map['id'] as String,
            title: map['title'] as String,
            description: map['description'] as String,
            severity: map['severity'] as String,
            timestamp: DateTime.tryParse(map['time'] as String? ?? ''),
          ),
        )
        .toList();
    alerts.sort(
      (first, second) => (second.timestamp ?? DateTime(0)).compareTo(
        first.timestamp ?? DateTime(0),
      ),
    );
    return alerts;
  }

  // --- Audit Logs CRUD ---
  Future<int> insertAuditLog(AuditLog log) async {
    if (kIsWeb) return 0;
    Database db = await database;
    return await db.insert('audit_logs', {
      'action': log.action,
      'user': log.user,
      'timestamp': log.timestamp,
    });
  }

  Future<List<AuditLog>> getAuditLogs() async {
    if (kIsWeb) return [];
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'audit_logs',
      orderBy: 'id DESC',
    );
    return List.generate(maps.length, (i) {
      return AuditLog(
        maps[i]['action'] as String,
        maps[i]['user'] as String,
        maps[i]['timestamp'] as String,
      );
    });
  }
}
