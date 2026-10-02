import 'package:biomass_iot_app/features/alerts/alert.dart';
import 'package:biomass_iot_app/features/alerts/alert_timestamp.dart';
import 'package:biomass_iot_app/features/devices/device.dart';
import 'package:biomass_iot_app/features/telemetry/sensor_reading.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps an absent sensor value distinct from a zero reading', () {
    final missing = SensorReading.fromJson({'mq2_v': null}, DateTime(2026));
    final zero = SensorReading.fromJson({'mq2_v': 0}, DateTime(2026));

    expect(missing.mq2V, isNull);
    expect(zero.mq2V, 0);
  });

  test('serializes saved device details without credentials', () {
    final device = Device('1', 'ESP32', '192.168.1.42', 'AA:BB');

    expect(device.toJson(), {
      'id': '1',
      'name': 'ESP32',
      'ipAddress': '192.168.1.42',
      'macAddress': 'AA:BB',
    });
  });

  test('formats an unavailable alert timestamp', () {
    expect(formatAlertTimestamp(null), 'Timestamp unavailable');
  });

  test('alert preserves its supplied timestamp', () {
    final time = DateTime(2026, 10, 2, 12);
    final alert = Alert(
      id: 'a1',
      title: 'Gas',
      description: 'High gas',
      severity: 'critical',
      timestamp: time,
    );

    expect(alert.timestamp, time);
  });
}
