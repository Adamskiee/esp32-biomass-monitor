import 'dart:math';

import 'attempt_comparison.dart';
import 'attempt_reading.dart';

class AttemptComparisonService {
  const AttemptComparisonService();

  AttemptComparison compare(
    List<AttemptReading> unfiltered,
    List<AttemptReading> filtered,
  ) => AttemptComparison(
    ComparisonMetric.values
        .map((metric) => _compare(metric, unfiltered, filtered))
        .toList(growable: false),
  );

  MetricComparison _compare(
    ComparisonMetric metric,
    List<AttemptReading> unfiltered,
    List<AttemptReading> filtered,
  ) {
    final unfilteredSeries = _series(metric, unfiltered);
    final filteredSeries = _series(metric, filtered);
    final before = _summary(unfilteredSeries);
    final after = _summary(filteredSeries);
    final difference = before.average == null || after.average == null
        ? null
        : after.average! - before.average!;
    return MetricComparison(
      metric: metric,
      unfiltered: before,
      filtered: after,
      unfilteredSeries: unfilteredSeries,
      filteredSeries: filteredSeries,
      difference: difference,
      percentageDifference: difference == null || before.average == 0
          ? null
          : difference / before.average! * 100,
    );
  }

  List<SeriesPoint> _series(
    ComparisonMetric metric,
    List<AttemptReading> readings,
  ) => readings
      .map((reading) => (reading, metric.valueOf(reading)))
      .where((pair) => pair.$2?.isFinite ?? false)
      .map((pair) => SeriesPoint(pair.$1.elapsed, pair.$2!))
      .toList(growable: false);
  ReadingSummary _summary(List<SeriesPoint> series) {
    if (series.isEmpty) return const ReadingSummary();
    final values = series.map((point) => point.value).toList(growable: false);
    final average =
        values.reduce((total, value) => total + value) / values.length;
    return ReadingSummary(
      average: average,
      minimum: values.reduce(min),
      maximum: values.reduce(max),
    );
  }
}
