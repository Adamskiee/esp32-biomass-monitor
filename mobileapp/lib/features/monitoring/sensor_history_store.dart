import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

abstract interface class SensorHistoryReader {
  Future<List<SensorData>> getSensorData({
    int limit,
    int offset,
    int? throughId,
  });

  Future<int> getLatestSensorDataId();

  Future<int> getSensorDataCount({int? throughId});
}

class SensorHistoryStore implements SensorHistoryReader {
  SensorHistoryStore(this._database);

  final AppDatabase _database;

  Future<int> insertSensorData(SensorData data) async {
    if (kIsWeb) return 0;
    return (await _database.database).insert('sensor_data', {
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

  @override
  Future<List<SensorData>> getSensorData({
    int limit = 100,
    int offset = 0,
    int? throughId,
  }) async {
    if (kIsWeb) return [];
    final rows = await (await _database.database).query(
      'sensor_data',
      where: throughId == null ? null : 'id <= ?',
      whereArgs: throughId == null ? null : [throughId],
      orderBy: 'id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_sensorDataFromRow).toList();
  }

  @override
  Future<int> getLatestSensorDataId() async {
    if (kIsWeb) return 0;
    final rows = await (await _database.database).rawQuery(
      'SELECT COALESCE(MAX(id), 0) AS latest_id FROM sensor_data',
    );
    return (rows.single['latest_id'] as num).toInt();
  }

  @override
  Future<int> getSensorDataCount({int? throughId}) async {
    if (kIsWeb) return 0;
    final rows = await (await _database.database).rawQuery(
      throughId == null
          ? 'SELECT COUNT(*) AS record_count FROM sensor_data'
          : 'SELECT COUNT(*) AS record_count FROM sensor_data WHERE id <= ?',
      throughId == null ? null : [throughId],
    );
    return (rows.single['record_count'] as num).toInt();
  }

  Future<List<SensorData>> getAggregatedSensorData(int hours) async {
    if (kIsWeb) return [];
    final cutoff = DateTime.now()
        .subtract(Duration(hours: hours))
        .toIso8601String();
    final rows = await (await _database.database).query(
      'sensor_data',
      where: 'timestamp >= ?',
      whereArgs: [cutoff],
      orderBy: 'timestamp ASC',
    );
    if (rows.isEmpty) return [];

    const targetPoints = 60;
    final step = (rows.length / targetPoints).ceil().clamp(1, rows.length);
    final data = <SensorData>[];
    for (var index = 0; index < rows.length; index += step) {
      final end = index + step < rows.length ? index + step : rows.length;
      final chunk = rows.sublist(index, end);
      data.add(
        SensorData(
          temperatureC: _average(chunk, 'temperature_c'),
          chamberTempC: _average(chunk, 'chamber_temp_c'),
          mq135V: _average(chunk, 'mq135_v'),
          mq2V: _average(chunk, 'mq2_v'),
          pm1_0UgM3: _average(chunk, 'pm1_0_ug_m3'),
          pm2_5UgM3: _average(chunk, 'pm2_5_ug_m3'),
          pm10UgM3: _average(chunk, 'pm10_ug_m3'),
          timestamp: DateTime.parse(chunk.last['timestamp']! as String),
        ),
      );
    }
    return data;
  }

  SensorData _sensorDataFromRow(Map<String, Object?> row) => SensorData(
    temperatureC: (row['temperature_c'] as num?)?.toDouble(),
    chamberTempC: (row['chamber_temp_c'] as num?)?.toDouble(),
    mq135V: (row['mq135_v'] as num?)?.toDouble(),
    mq2V: (row['mq2_v'] as num?)?.toDouble(),
    pm1_0UgM3: (row['pm1_0_ug_m3'] as num?)?.toDouble(),
    pm2_5UgM3: (row['pm2_5_ug_m3'] as num?)?.toDouble(),
    pm10UgM3: (row['pm10_ug_m3'] as num?)?.toDouble(),
    timestamp: DateTime.parse(row['timestamp']! as String),
  );

  double? _average(List<Map<String, Object?>> rows, String column) {
    final values = rows
        .map((row) => row[column] as num?)
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((total, value) => total + value) / values.length;
  }
}
