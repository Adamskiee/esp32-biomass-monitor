import 'package:biomass_iot_app/features/monitoring/widgets/sensor_metric_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final isCompact in [true, false]) {
    testWidgets('keeps normal, fault, and warmup cards equal height', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    width: isCompact ? 150 : 260,
                    child: SensorMetricCard(
                      isCompact: isCompact,
                      title: 'Humidity',
                      value: 60,
                      suffix: ' %',
                      icon: Icons.water_drop,
                      color: Colors.blue,
                      theme: ThemeData.light(),
                    ),
                  ),
                  SizedBox(
                    width: isCompact ? 150 : 260,
                    child: SensorMetricCard(
                      isCompact: isCompact,
                      title: 'MQ2 Smoke',
                      value: null,
                      suffix: ' V',
                      icon: Icons.cloud,
                      color: Colors.purple,
                      theme: ThemeData.light(),
                    ),
                  ),
                  SizedBox(
                    width: isCompact ? 150 : 260,
                    child: SensorMetricCard(
                      isCompact: isCompact,
                      title: 'MQ135 Gas',
                      value: null,
                      suffix: ' V',
                      icon: Icons.cloud,
                      color: Colors.blue,
                      theme: ThemeData.light(),
                      statusText: 'Warming up: 5 min remaining',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));

      final cards = find.byType(SensorMetricCard);
      final normalCardHeight = tester.getSize(cards.at(0)).height;

      expect(tester.getSize(cards.at(1)).height, normalCardHeight);
      expect(tester.getSize(cards.at(2)).height, normalCardHeight);
      expect(
        tester.getRect(find.text('60 %')).top -
            tester.getRect(find.text('Humidity')).bottom,
        lessThanOrEqualTo(8),
      );
      expect(
        tester.getRect(cards.at(0)).bottom -
            tester.getRect(find.text('60 %')).bottom,
        lessThanOrEqualTo(28),
      );
    });
  }

  testWidgets('shows a sensor fault instead of zero for a missing reading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SensorMetricCard(
            title: 'MQ2 Smoke',
            value: null,
            suffix: ' V',
            icon: Icons.cloud,
            color: Colors.purple,
            theme: ThemeData.light(),
            decimals: 2,
          ),
        ),
      ),
    );

    expect(find.text('--'), findsOneWidget);
    expect(find.text('Sensor fault'), findsOneWidget);
    expect(find.text('0.00 V'), findsNothing);
  });

  testWidgets('shows a genuine zero reading as zero', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SensorMetricCard(
            title: 'MQ2 Smoke',
            value: 0.0,
            suffix: ' V',
            icon: Icons.cloud,
            color: Colors.purple,
            theme: ThemeData.light(),
            decimals: 2,
          ),
        ),
      ),
    );

    expect(find.text('0.00 V'), findsOneWidget);
    expect(find.text('Sensor fault'), findsNothing);
  });

  testWidgets('shows warmup status instead of a sensor fault', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SensorMetricCard(
            title: 'MQ2 Smoke',
            value: null,
            suffix: ' V',
            icon: Icons.cloud,
            color: Colors.purple,
            theme: ThemeData.light(),
            statusText: 'Warming up: 5 min remaining',
          ),
        ),
      ),
    );

    expect(find.text('Warming up: 5 min remaining'), findsOneWidget);
    expect(find.text('Sensor fault'), findsNothing);
  });
}
