import 'package:biomass_iot_app/features/experiments/attempt_comparison.dart';
import 'package:biomass_iot_app/features/experiments/attempt_comparison_service.dart';
import 'package:biomass_iot_app/features/experiments/attempt_reading.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

AttemptReading reading(Duration elapsed, SensorData data) => AttemptReading(
  attemptId: 1,
  recordedAt: DateTime.utc(2026, 10, 7).add(elapsed),
  elapsed: elapsed,
  data: data,
);

SensorData data({
  double? mq2,
  double? mq135,
  double? temperature,
  double? humidity,
  double? pm1,
  double? pm25,
  double? pm10,
}) => SensorData(
  mq2V: mq2,
  mq135V: mq135,
  temperatureC: temperature,
  humidityPercent: humidity,
  pm1UgM3: pm1,
  pm25UgM3: pm25,
  pm10UgM3: pm10,
  timestamp: DateTime.utc(2026, 10, 7),
);

void main() {
  const service = AttemptComparisonService();

  test('calculates summaries and signed changes for every metric', () {
    final comparison = service.compare(
      [
        reading(
          Duration.zero,
          data(
            mq2: 2,
            mq135: 4,
            temperature: 20,
            humidity: 50,
            pm1: 10,
            pm25: 100,
            pm10: 30,
          ),
        ),
      ],
      [
        reading(
          Duration.zero,
          data(
            mq2: 1,
            mq135: 2,
            temperature: 10,
            humidity: 25,
            pm1: 5,
            pm25: 75,
            pm10: 15,
          ),
        ),
      ],
    );
    expect(comparison.metrics, hasLength(7));
    for (final metric in comparison.metrics) {
      expect(metric.unfiltered.average, isNotNull);
      expect(metric.filtered.average, isNotNull);
      expect(
        metric.difference,
        metric.filtered.average! - metric.unfiltered.average!,
      );
    }
    final pm25 = comparison.forMetric(ComparisonMetric.pm25);
    expect(
      pm25.unfiltered,
      const ReadingSummary(average: 100, minimum: 100, maximum: 100),
    );
    expect(pm25.difference, -25);
    expect(pm25.percentageDifference, -25);
  });

  test(
    'omits missing and non-finite readings without interpolating series',
    () {
      final comparison = service.compare(
        [
          reading(Duration.zero, data(pm25: 0, pm1: double.nan)),
          reading(
            const Duration(seconds: 1),
            data(pm25: double.infinity, pm1: double.negativeInfinity),
          ),
        ],
        [
          reading(const Duration(seconds: 2), data(pm25: 4)),
          reading(const Duration(seconds: 4), data(pm25: 6)),
        ],
      );
      final pm25 = comparison.forMetric(ComparisonMetric.pm25);
      expect(pm25.difference, 5);
      expect(pm25.percentageDifference, isNull);
      expect(pm25.unfilteredSeries.map((point) => point.elapsed), [
        Duration.zero,
      ]);
      expect(pm25.filteredSeries.map((point) => point.elapsed), [
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ]);
      final pm1 = comparison.forMetric(ComparisonMetric.pm1);
      expect(pm1.difference, isNull);
      expect(pm1.unfilteredSeries, isEmpty);
    },
  );
}
