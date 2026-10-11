import 'package:biomass_iot_app/features/experiments/attempt_comparison.dart';
import 'package:biomass_iot_app/features/experiments/attempt_comparison_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders all metrics with neutral summaries and charts', (
    tester,
  ) async {
    final comparison = AttemptComparison(
      ComparisonMetric.values
          .map(
            (metric) => MetricComparison(
              metric: metric,
              unfiltered: const ReadingSummary(average: 20),
              filtered: const ReadingSummary(average: 15),
              unfilteredSeries: const [SeriesPoint(Duration(seconds: 5), 20)],
              filteredSeries: const [SeriesPoint(Duration(seconds: 9), 15)],
              difference: -5,
              percentageDifference: -25,
            ),
          )
          .toList(),
    );

    await tester.pumpWidget(
      MaterialApp(home: AttemptComparisonScreen(comparison: comparison)),
    );

    expect(find.text('MQ-2 (V)'), findsOneWidget);
    expect(find.text('25.0% lower with filtration'), findsWidgets);
    expect(find.byType(LineChart), findsWidgets);
    expect(find.textContaining('successful'), findsNothing);
  });
}
