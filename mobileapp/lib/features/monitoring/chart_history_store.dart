import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/storage/app_database.dart';
import 'chart_history.dart';
import 'sensor_data.dart';

class ChartHistoryStore implements ChartHistoryReader {
  ChartHistoryStore(this._database);

  final AppDatabase _database;

  @override
  Future<ChartHistory> load({
    DateTime? since,
    required DateTime through,
  }) async {
    if (kIsWeb) return ChartHistory.fromReadings([]);
    final database = await _database.database;
    return database.transaction((transaction) async {
      final where =
          'julianday(timestamp) <= julianday(?)${since == null ? '' : ' AND julianday(timestamp) >= julianday(?)'}';
      final arguments = [
        through.toIso8601String(),
        if (since != null) since.toIso8601String(),
      ];
      final aggregates = SensorMetric.values
          .expand(
            (metric) => [
              'MAX(${metric.column}) AS ${metric.column}_peak',
              'AVG(${metric.column}) AS ${metric.column}_average',
            ],
          )
          .join(', ');
      final rows = await transaction.rawQuery('''
        SELECT MIN(julianday(timestamp)) AS first_time,
          MAX(julianday(timestamp)) AS last_time, $aggregates
        FROM sensor_data WHERE $where
      ''', arguments);
      final summary = rows.single;
      final statistics = {
        for (final metric in SensorMetric.values)
          metric: SensorStatistics(
            peak: (summary['${metric.column}_peak'] as num?)?.toDouble(),
            average: (summary['${metric.column}_average'] as num?)?.toDouble(),
          ),
      };
      final first = summary['first_time'] as num?;
      final last = summary['last_time'] as num?;
      if (first == null || last == null) {
        return ChartHistory(points: [], statistics: statistics);
      }
      final averages = SensorMetric.values
          .map((metric) => 'AVG(${metric.column}) AS ${metric.column}')
          .join(', ');
      // Bound chart data in SQLite; summaries above retain every original value.
      final bucket = first == last
          ? '0'
          : 'CAST((julianday(timestamp) - ?) / ? * 59 AS INTEGER)';
      final points = await transaction.rawQuery(
        '''
        SELECT $averages, MAX(julianday(timestamp)) AS recorded_at,
          $bucket AS bucket
        FROM sensor_data WHERE $where
        GROUP BY bucket ORDER BY recorded_at ASC
      ''',
        [
          if (first != last) ...[first, last - first],
          ...arguments,
        ],
      );
      return ChartHistory(
        points: points
            .map(
              (row) => SensorData(
                temperatureC: (row['temperature_c'] as num?)?.toDouble(),
                chamberTempC: (row['chamber_temp_c'] as num?)?.toDouble(),
                humidityPercent: (row['humidity_percent'] as num?)?.toDouble(),
                mq2V: (row['mq2_v'] as num?)?.toDouble(),
                mq135V: (row['mq135_v'] as num?)?.toDouble(),
                pm1_0UgM3: (row['pm1_0_ug_m3'] as num?)?.toDouble(),
                pm2_5UgM3: (row['pm2_5_ug_m3'] as num?)?.toDouble(),
                pm10UgM3: (row['pm10_ug_m3'] as num?)?.toDouble(),
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  (((row['recorded_at'] as num) - 2440587.5) *
                          Duration.millisecondsPerDay)
                      .round(),
                  isUtc: true,
                ),
              ),
            )
            .toList(),
        statistics: statistics,
      );
    });
  }
}
