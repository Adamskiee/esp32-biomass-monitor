import 'package:biomass_iot_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
