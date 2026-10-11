import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'attempt_comparison.dart';

class AttemptComparisonScreen extends StatelessWidget {
  const AttemptComparisonScreen({super.key, required this.comparison});
  final AttemptComparison comparison;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Attempt comparison')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: comparison.metrics
          .map((item) => _MetricCard(comparison: item))
          .toList(growable: false),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.comparison});
  final MetricComparison comparison;

  @override
  Widget build(BuildContext context) {
    final metric = comparison.metric;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${metric.label} (${metric.unit})'),
            const SizedBox(height: 8),
            Text(
              'Without: ${_value(comparison.unfiltered.average, metric)} · With: ${_value(comparison.filtered.average, metric)}',
            ),
            const SizedBox(height: 4),
            Text(_change(comparison)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: MetricComparisonChart(comparison: comparison),
            ),
          ],
        ),
      ),
    );
  }

  String _value(double? value, ComparisonMetric metric) => value == null
      ? 'No data'
      : '${value.toStringAsFixed(metric.decimalPlaces)} ${metric.unit}';
  String _change(MetricComparison item) {
    final percentage = item.percentageDifference;
    if (item.difference == null) return 'No data';
    if (percentage == null) return 'Not available';
    if (percentage < 0)
      return '${percentage.abs().toStringAsFixed(1)}% lower with filtration';
    if (percentage > 0)
      return '${percentage.toStringAsFixed(1)}% higher with filtration';
    return 'No difference';
  }
}

class MetricComparisonChart extends StatelessWidget {
  const MetricComparisonChart({super.key, required this.comparison});
  final MetricComparison comparison;

  @override
  Widget build(BuildContext context) {
    final points = [
      ...comparison.unfilteredSeries,
      ...comparison.filteredSeries,
    ];
    if (points.isEmpty) return const Center(child: Text('No data'));
    final values = points.map((point) => point.value);
    final minimum = values.reduce(min);
    final maximum = values.reduce(max);
    final padding = minimum == maximum
        ? max(1, minimum.abs() * .1)
        : (maximum - minimum) * .1;
    final maxSeconds = points
        .map((point) => point.elapsed.inMilliseconds / 1000)
        .reduce(max);
    return LineChart(
      LineChartData(
        minY: minimum - padding,
        maxY: maximum + padding,
        minX: 0,
        maxX: max(1, maxSeconds),
        gridData: const FlGridData(show: true),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          _line(comparison.unfilteredSeries, Colors.orange),
          _line(comparison.filteredSeries, Colors.teal),
        ],
      ),
    );
  }

  LineChartBarData _line(List<SeriesPoint> points, Color color) =>
      LineChartBarData(
        spots: points
            .map(
              (point) =>
                  FlSpot(point.elapsed.inMilliseconds / 1000, point.value),
            )
            .toList(growable: false),
        color: color,
        barWidth: 2,
        dotData: const FlDotData(show: false),
      );
}
