import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports PMS columns', () {
    final csv = buildTelemetryCsv([
      SensorData(pm1_0UgM3: 8, timestamp: DateTime.utc(2026, 10, 8)),
    ]);

    expect(csv, contains('PM1.0(ug/m3),PM2.5(ug/m3),PM10(ug/m3)'));
    expect(csv, contains('8.00,,\n'));
  });
}
