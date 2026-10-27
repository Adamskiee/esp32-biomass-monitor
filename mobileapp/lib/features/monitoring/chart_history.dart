import 'dart:math' as math;

import 'sensor_data.dart';

enum SensorMetric {
  ambient('temperature_c'),
  chamber('chamber_temp_c'),
  humidity('humidity_percent'),
  mq2('mq2_v'),
  mq135('mq135_v'),
  pm1('pm1_0_ug_m3'),
  pm25('pm2_5_ug_m3'),
  pm10('pm10_ug_m3');

  const SensorMetric(this.column);
  final String column;

  double? valueFor(SensorData data) => switch (this) {
    ambient => data.temperatureC,
    chamber => data.chamberTempC,
    humidity => data.humidityPercent,
    mq2 => data.mq2V,
    mq135 => data.mq135V,
    pm1 => data.pm1_0UgM3,
    pm25 => data.pm2_5UgM3,
    pm10 => data.pm10UgM3,
  };
}

class SensorStatistics {
  const SensorStatistics({this.peak, this.average});

  final double? peak;
  final double? average;
}

class ChartHistory {
  ChartHistory({
    required List<SensorData> points,
    required Map<SensorMetric, SensorStatistics> statistics,
  }) : points = List.unmodifiable(points),
       statistics = Map.unmodifiable(statistics);

  factory ChartHistory.fromReadings(List<SensorData> readings) {
    final statistics = <SensorMetric, SensorStatistics>{};
    for (final metric in SensorMetric.values) {
      final values = readings.map(metric.valueFor).whereType<double>().toList();
      statistics[metric] = values.isEmpty
          ? const SensorStatistics()
          : SensorStatistics(
              peak: values.reduce(math.max),
              average: values.reduce((a, b) => a + b) / values.length,
            );
    }
    return ChartHistory(points: readings, statistics: statistics);
  }

  final List<SensorData> points;
  final Map<SensorMetric, SensorStatistics> statistics;
}

abstract interface class ChartHistoryReader {
  Future<ChartHistory> load({DateTime? since, required DateTime through});
}
