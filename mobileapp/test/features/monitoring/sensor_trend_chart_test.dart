import 'package:biomass_iot_app/features/monitoring/chart_history.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/widgets/sensor_trend_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final points = [
    SensorData(temperatureC: 10, timestamp: DateTime(2026, 10, 27, 9)),
    SensorData(temperatureC: 30, timestamp: DateTime(2026, 10, 27, 10)),
  ];
  const series = [
    SensorTrendSeries(
      label: 'Ambient',
      color: Colors.orange,
      metric: SensorMetric.ambient,
    ),
    SensorTrendSeries(
      label: 'Chamber',
      color: Colors.red,
      metric: SensorMetric.chamber,
    ),
  ];

  Future<void> mount(
    WidgetTester tester, {
    bool isLive = false,
    double width = 450,
    double scale = 1,
    List<SensorData>? history,
    Map<SensorMetric, SensorStatistics>? statistics,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final readings = history ?? points;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: SensorTrendChart(
              title: 'Temperature',
              icon: Icons.thermostat,
              unit: '°C',
              history: readings,
              statistics:
                  statistics ?? ChartHistory.fromReadings(readings).statistics,
              height: 200,
              series: series,
              isLive: isLive,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Live summaries expand and collapse below the graph', (
    tester,
  ) async {
    await mount(tester, isLive: true);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('30.0'), findsNothing);
    expect(find.text('Peak & average'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Peak & average')).dy,
      greaterThan(tester.getBottomLeft(find.byType(LineChart)).dy),
    );
    await tester.tap(find.text('Peak & average'));
    await tester.pumpAndSettle();
    expect(find.text('30.0'), findsOneWidget);
    expect(find.text('20.0'), findsOneWidget);
    expect(find.text('No data'), findsNWidgets(2));
    await tester.tap(find.text('Peak & average'));
    await tester.pumpAndSettle();
    expect(find.text('30.0'), findsNothing);
  });

  testWidgets(
    'historical table identifies series once and shows raw statistics below graph',
    (tester) async {
      await mount(
        tester,
        statistics: {
          SensorMetric.ambient: const SensorStatistics(peak: 900, average: 25),
        },
      );
      expect(find.text('Ambient'), findsOneWidget);
      expect(find.text('Chamber'), findsOneWidget);
      expect(find.text('Peak (°C)'), findsOneWidget);
      expect(find.text('Average (°C)'), findsOneWidget);
      expect(find.text('900.0'), findsOneWidget);
      expect(find.text('25.0'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(Table)).dy,
        greaterThan(tester.getBottomLeft(find.byType(LineChart)).dy),
      );
      expect(find.text('Peak & average'), findsNothing);
      expect(
        tester.getRect(find.text('900.0')).right,
        closeTo(tester.getRect(find.text('No data').first).right, 1),
      );
    },
  );

  testWidgets(
    'large values and sensor labels remain readable with scaled text',
    (tester) async {
      await mount(
        tester,
        width: 320,
        scale: 1.5,
        statistics: {
          SensorMetric.ambient: const SensorStatistics(
            peak: 65535,
            average: 12345.6,
          ),
        },
      );
      expect(find.text('65535.0'), findsOneWidget);
      expect(find.text('12345.6'), findsOneWidget);
      expect(tester.getSize(find.text('65535.0')).height, lessThan(30));
      expect(tester.getSize(find.text('Ambient')).height, lessThan(30));
      expect(find.text('Chamber'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'plot context includes dates across years without changing sample positions',
    (tester) async {
      await mount(
        tester,
        history: [
          SensorData(temperatureC: 10, timestamp: DateTime(2025, 12, 31, 23)),
          SensorData(temperatureC: 30, timestamp: DateTime(2026, 1, 2, 10)),
        ],
      );
      expect(find.text('Dec 31, 2025 · 23:00'), findsOneWidget);
      expect(find.text('Jan 2, 2026 · 10:00'), findsOneWidget);
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.single.spots, [
        const FlSpot(0, 10),
        const FlSpot(1, 30),
      ]);
    },
  );

  testWidgets(
    'time context ignores missing values outside the plotted series',
    (tester) async {
      await mount(
        tester,
        history: [
          SensorData(mq2V: 1, timestamp: DateTime(2026, 10, 27, 9)),
          SensorData(temperatureC: 30, timestamp: DateTime(2026, 10, 27, 10)),
          SensorData(mq2V: 2, timestamp: DateTime(2026, 10, 27, 11)),
        ],
      );
      expect(find.text('Reading at Oct 27, 2026 · 10:00'), findsOneWidget);
      expect(find.text('09:00'), findsNothing);
      expect(find.text('11:00'), findsNothing);
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.single.spots, [
        FlSpot.nullSpot,
        const FlSpot(1, 30),
        FlSpot.nullSpot,
      ]);
    },
  );

  testWidgets('a single reading has one time label', (tester) async {
    await mount(tester, history: [points.first]);
    expect(find.text('Reading at Oct 27, 2026 · 09:00'), findsOneWidget);
    expect(find.text('First reading'), findsNothing);
    expect(find.text('Last reading'), findsNothing);
  });

  testWidgets('missing chart retains sensor identities and no-data summary', (
    tester,
  ) async {
    await mount(
      tester,
      history: [SensorData(timestamp: DateTime(2026, 10, 27))],
    );
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('No readings available for Temperature'), findsOneWidget);
    expect(find.text('Ambient'), findsOneWidget);
    expect(find.text('Chamber'), findsOneWidget);
    expect(find.text('No data'), findsNWidgets(4));
  });
}
