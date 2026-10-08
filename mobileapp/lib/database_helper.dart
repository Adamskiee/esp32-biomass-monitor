import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'features/alerts/alert_item.dart';
import 'features/monitoring/sensor_data.dart';
import 'features/safety/audit_log.dart';
import 'core/storage/database_provider.dart';
import 'core/storage/database_schema.dart';

class DatabaseHelper implements DatabaseProvider {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  @override
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
      version: DatabaseSchema.version,
      onConfigure: DatabaseSchema.configure,
      onCreate: DatabaseSchema.create,
      onUpgrade: DatabaseSchema.upgrade,
    );
  }

  // --- Sensor Data CRUD ---
  Future<int> insertSensorData(SensorData data) async {
    if (kIsWeb) return 0;
    Database db = await database;
    return await db.insert('sensor_data', {
      'temperature_c': data.temperatureC,
      'humidity_percent': data.humidityPercent,
      'chamber_temp_c': data.chamberTempC,
      'mq135_v': data.mq135V,
      'mq2_v': data.mq2V,
      'pm1_ug_m3': data.pm1UgM3,
      'pm25_ug_m3': data.pm25UgM3,
      'pm10_ug_m3': data.pm10UgM3,
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
        humidityPercent: maps[i]['humidity_percent'] as double?,
        chamberTempC: maps[i]['chamber_temp_c'] as double?,
        mq135V: maps[i]['mq135_v'] as double?,
        mq2V: maps[i]['mq2_v'] as double?,
        pm1UgM3: maps[i]['pm1_ug_m3'] as double?,
        pm25UgM3: maps[i]['pm25_ug_m3'] as double?,
        pm10UgM3: maps[i]['pm10_ug_m3'] as double?,
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

      final columns = [
        'temperature_c',
        'humidity_percent',
        'chamber_temp_c',
        'mq135_v',
        'mq2_v',
        'pm1_ug_m3',
        'pm25_ug_m3',
        'pm10_ug_m3',
      ];
      final sums = {for (final column in columns) column: 0.0};
      final counts = {for (final column in columns) column: 0};

      for (var row in chunk) {
        for (final column in columns) {
          final value = row[column] as num?;
          if (value != null) {
            sums[column] = sums[column]! + value.toDouble();
            counts[column] = counts[column]! + 1;
          }
        }
      }

      aggregated.add(
        SensorData(
          temperatureC: _mean(sums, counts, 'temperature_c'),
          humidityPercent: _mean(sums, counts, 'humidity_percent'),
          chamberTempC: _mean(sums, counts, 'chamber_temp_c'),
          mq135V: _mean(sums, counts, 'mq135_v'),
          mq2V: _mean(sums, counts, 'mq2_v'),
          pm1UgM3: _mean(sums, counts, 'pm1_ug_m3'),
          pm25UgM3: _mean(sums, counts, 'pm25_ug_m3'),
          pm10UgM3: _mean(sums, counts, 'pm10_ug_m3'),
          timestamp: DateTime.parse(chunk.last['timestamp'] as String),
        ),
      );
    }

    return aggregated;
  }

  double? _mean(
    Map<String, double> sums,
    Map<String, int> counts,
    String column,
  ) => counts[column] == 0 ? null : sums[column]! / counts[column]!;

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
