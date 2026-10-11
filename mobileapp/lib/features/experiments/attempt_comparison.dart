import 'attempt_reading.dart';

enum ComparisonMetric { mq2, mq135, temperature, humidity, pm1, pm25, pm10 }

extension ComparisonMetricDetails on ComparisonMetric {
  String get label => switch (this) {
    ComparisonMetric.mq2 => 'MQ-2',
    ComparisonMetric.mq135 => 'MQ-135',
    ComparisonMetric.temperature => 'DHT-22 temperature',
    ComparisonMetric.humidity => 'DHT-22 humidity',
    ComparisonMetric.pm1 => 'PM1.0',
    ComparisonMetric.pm25 => 'PM2.5',
    ComparisonMetric.pm10 => 'PM10',
  };
  String get unit => switch (this) {
    ComparisonMetric.mq2 || ComparisonMetric.mq135 => 'V',
    ComparisonMetric.temperature => '°C',
    ComparisonMetric.humidity => '%',
    _ => 'µg/m³',
  };
  int get decimalPlaces => switch (this) {
    ComparisonMetric.mq2 || ComparisonMetric.mq135 => 2,
    ComparisonMetric.temperature || ComparisonMetric.humidity => 1,
    _ => 0,
  };
  double? valueOf(AttemptReading reading) => switch (this) {
    ComparisonMetric.mq2 => reading.data.mq2V,
    ComparisonMetric.mq135 => reading.data.mq135V,
    ComparisonMetric.temperature => reading.data.temperatureC,
    ComparisonMetric.humidity => reading.data.humidityPercent,
    ComparisonMetric.pm1 => reading.data.pm1UgM3,
    ComparisonMetric.pm25 => reading.data.pm25UgM3,
    ComparisonMetric.pm10 => reading.data.pm10UgM3,
  };
}

class ReadingSummary {
  const ReadingSummary({this.average, this.minimum, this.maximum});
  final double? average;
  final double? minimum;
  final double? maximum;
  @override
  bool operator ==(Object other) =>
      other is ReadingSummary &&
      other.average == average &&
      other.minimum == minimum &&
      other.maximum == maximum;
  @override
  int get hashCode => Object.hash(average, minimum, maximum);
}

class SeriesPoint {
  const SeriesPoint(this.elapsed, this.value);
  final Duration elapsed;
  final double value;
}

class MetricComparison {
  const MetricComparison({
    required this.metric,
    required this.unfiltered,
    required this.filtered,
    required this.unfilteredSeries,
    required this.filteredSeries,
    this.difference,
    this.percentageDifference,
  });
  final ComparisonMetric metric;
  final ReadingSummary unfiltered;
  final ReadingSummary filtered;
  final List<SeriesPoint> unfilteredSeries;
  final List<SeriesPoint> filteredSeries;
  final double? difference;
  final double? percentageDifference;
}

class AttemptComparison {
  const AttemptComparison(this.metrics);
  final List<MetricComparison> metrics;
  MetricComparison forMetric(ComparisonMetric metric) =>
      metrics.singleWhere((item) => item.metric == metric);
}
