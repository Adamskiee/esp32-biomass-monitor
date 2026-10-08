import 'package:biomass_iot_app/features/monitoring/pms_readings.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows particulate values and unavailable state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            PmsReadings(data: SensorData(pm1_0UgM3: 0, pm2_5UgM3: 12, pm10UgM3: 18, timestamp: DateTime.now())),
            PmsReadings(data: SensorData(timestamp: DateTime.now())),
          ],
        ),
      ),
    );

    expect(find.text('0 µg/m³'), findsOneWidget);
    expect(find.text('12 µg/m³'), findsOneWidget);
    expect(find.text('18 µg/m³'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(3));
  });
}
