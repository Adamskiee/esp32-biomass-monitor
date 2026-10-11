import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'core/storage/app_database.dart';
import 'core/storage/database_provider.dart';

import 'features/alerts/alert_item.dart';
import 'features/monitoring/sensor_data.dart';
import 'features/safety/audit_log.dart';

class DatabaseHelper implements DatabaseProvider {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static final AppDatabase _defaultStorage = AppDatabase();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal() : _storage = null;
  DatabaseHelper.forTesting(AppDatabase storage) : _storage = storage;

  final AppDatabase? _storage;

  @override
  Future<Database> get database {
    if (kIsWeb) throw UnsupportedError('SQLite is not supported on the Web');
    return (_storage ?? _defaultStorage).database;
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
      'pm1_0_ug_m3': data.pm1_0UgM3,
      'pm2_5_ug_m3': data.pm2_5UgM3,
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
        chamberTempC: maps[i]['chamber_temp_c'] as double?,
        mq135V: maps[i]['mq135_v'] as double?,
        mq2V: maps[i]['mq2_v'] as double?,
        pm1_0UgM3: (maps[i]['pm1_0_ug_m3'] as num?)?.toDouble(),
        pm2_5UgM3: (maps[i]['pm2_5_ug_m3'] as num?)?.toDouble(),
        pm10UgM3: (maps[i]['pm10_ug_m3'] as num?)?.toDouble(),
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
      double sumPm1 = 0, sumPm25 = 0, sumPm10 = 0;
      int countTempC = 0, countChamberC = 0, countMq135 = 0, countMq2 = 0;
      int countPm1 = 0, countPm25 = 0, countPm10 = 0;

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
        if (row['pm1_0_ug_m3'] != null) {
          sumPm1 += (row['pm1_0_ug_m3'] as num).toDouble();
          countPm1++;
        }
        if (row['pm2_5_ug_m3'] != null) {
          sumPm25 += (row['pm2_5_ug_m3'] as num).toDouble();
          countPm25++;
        }
        if (row['pm10_ug_m3'] != null) {
          sumPm10 += (row['pm10_ug_m3'] as num).toDouble();
          countPm10++;
        }
      }

      aggregated.add(
        SensorData(
          temperatureC: countTempC > 0 ? sumTempC / countTempC : null,
          chamberTempC: countChamberC > 0 ? sumChamberC / countChamberC : null,
          mq135V: countMq135 > 0 ? sumMq135 / countMq135 : null,
          mq2V: countMq2 > 0 ? sumMq2 / countMq2 : null,
          pm1_0UgM3: countPm1 > 0 ? sumPm1 / countPm1 : null,
          pm2_5UgM3: countPm25 > 0 ? sumPm25 / countPm25 : null,
          pm10UgM3: countPm10 > 0 ? sumPm10 / countPm10 : null,
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
