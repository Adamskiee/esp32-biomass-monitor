import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class SensorHistoryStore {
  SensorHistoryStore(this._database);

  final AppDatabase _database;

  Future<int> insertSensorData(SensorData data) async {
    if (kIsWeb) return 0;
    return (await _database.database).insert('sensor_data', {
      'temperature_c': data.temperatureC,
      'chamber_temp_c': data.chamberTempC,
      'mq135_v': data.mq135V,
      'mq2_v': data.mq2V,
      'timestamp': data.timestamp.toIso8601String(),
    });
  }

  Future<List<SensorData>> getSensorData({int limit = 100}) async {
    if (kIsWeb) return [];
    final rows = await (await _database.database).query(
      'sensor_data',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(_sensorDataFromRow).toList();
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
