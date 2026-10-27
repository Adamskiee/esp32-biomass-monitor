import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/monitoring/chart_history.dart';
import 'package:biomass_iot_app/features/monitoring/chart_history_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_history_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase database;
  late SensorHistoryStore readings;
  late ChartHistoryStore charts;
  final start = DateTime.utc(2026, 10, 1);

  setUpAll(sqfliteFfiInit);
  setUp(() {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    readings = SensorHistoryStore(database);
    charts = ChartHistoryStore(database);
  });
  tearDown(() => database.close());

  test('all time keeps old peaks and averages every raw reading', () async {
    for (var i = 0; i < 121; i++) {
      await readings.insertSensorData(
        SensorData(
          temperatureC: i == 0 ? 1000 : 10,
          humidityPercent: i == 0 ? null : 50,
          chamberTempC: 200,
          mq135V: 0.5,
          mq2V: 1.25,
          pm1_0UgM3: 1,
          pm2_5UgM3: 2,
          pm10UgM3: 3,
          timestamp: start.add(Duration(minutes: i)),
        ),
      );
    }
    final result = await charts.load(
      through: start.add(const Duration(days: 1)),
    );
    expect(result.statistics[SensorMetric.ambient]!.peak, 1000);
    expect(
      result.statistics[SensorMetric.ambient]!.average,
      closeTo(2200 / 121, 0.00001),
    );
    expect(result.statistics[SensorMetric.humidity]!.average, 50);
    expect(result.statistics[SensorMetric.chamber]!.peak, 200);
    expect(result.statistics[SensorMetric.mq135]!.average, 0.5);
    expect(result.statistics[SensorMetric.mq2]!.average, 1.25);
    expect(result.statistics[SensorMetric.pm1]!.average, 1);
    expect(result.statistics[SensorMetric.pm25]!.average, 2);
    expect(result.statistics[SensorMetric.pm10]!.average, 3);
    expect(result.points.length, inInclusiveRange(1, 60));
    expect(
      result.points.first.timestamp.isBefore(result.points.last.timestamp),
      isTrue,
    );
    expect(result.points.any((p) => p.temperatureC == 1000), isFalse);
  });

  test(
    'period includes both boundaries and excludes older and future data',
    () async {
      for (final minutes in [-1, 0, 60, 61]) {
        await readings.insertSensorData(
          SensorData(
            temperatureC: minutes.toDouble(),
            timestamp: start.add(Duration(minutes: minutes)),
          ),
        );
      }
      final result = await charts.load(
        since: start,
        through: start.add(const Duration(hours: 1)),
      );
      expect(result.statistics[SensorMetric.ambient]!.peak, 60);
      expect(result.statistics[SensorMetric.ambient]!.average, 30);
    },
  );

  test('empty and null-only histories retain missing statistics', () async {
    final empty = await charts.load(through: start);
    expect(empty.points, isEmpty);
    expect(empty.statistics[SensorMetric.ambient]!.average, isNull);
    await readings.insertSensorData(SensorData(timestamp: start));
    final missing = await charts.load(through: start);
    expect(missing.points, hasLength(1));
    for (final metric in SensorMetric.values) {
      expect(missing.statistics[metric]!.peak, isNull);
      expect(missing.statistics[metric]!.average, isNull);
    }
  });

  test(
    'Live statistics ignore missing readings while retaining real zeros',
    () {
      final result = ChartHistory.fromReadings([
        SensorData(temperatureC: 0, timestamp: start),
        SensorData(temperatureC: 10, mq2V: 2, timestamp: start),
        SensorData(timestamp: start),
      ]);
      expect(result.statistics[SensorMetric.ambient]!.average, 5);
      expect(result.statistics[SensorMetric.ambient]!.peak, 10);
      expect(result.statistics[SensorMetric.mq2]!.average, 2);
      expect(result.statistics[SensorMetric.pm10]!.average, isNull);
    },
  );

  test('identical timestamps still produce a bounded chart', () async {
    for (var i = 0; i < 70; i++) {
      await readings.insertSensorData(
        SensorData(temperatureC: i.toDouble(), timestamp: start),
      );
    }
    final result = await charts.load(through: start);
    expect(result.points, hasLength(1));
    expect(result.statistics[SensorMetric.ambient]!.average, 34.5);
  });
}
