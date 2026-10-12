import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses particulate readings from mixed numeric JSON values', () {
    final reading = SensorData.fromJson({
      'pm1_0_ug_m3': 0,
      'pm2_5_ug_m3': 12.5,
      'pm10_ug_m3': 18,
    });

    expect(
      (reading.pm1_0UgM3, reading.pm2_5UgM3, reading.pm10UgM3),
      (0.0, 12.5, 18.0),
    );
  });

  test('treats null and omitted particulate readings as unavailable', () {
    final nullReading = SensorData.fromJson({
      'pm1_0_ug_m3': null,
      'pm2_5_ug_m3': null,
      'pm10_ug_m3': null,
    });
    final missingReading = SensorData.fromJson({});

    for (final reading in [nullReading, missingReading]) {
      expect(reading.pm1_0UgM3, isNull);
      expect(reading.pm2_5UgM3, isNull);
      expect(reading.pm10UgM3, isNull);
    }
  });

  test('parses nullable MQ responses and calibration identifiers', () {
    final reading = SensorData.fromJson({
      'mq2_response_ratio': 4,
      'mq135_response_ratio': null,
      'mq2_calibration_id': 12,
      'mq135_calibration_id': null,
    });

    expect(reading.mq2ResponseRatio, 4.0);
    expect(reading.mq135ResponseRatio, isNull);
    expect(reading.mq2CalibrationId, '12');
    expect(reading.mq135CalibrationId, isNull);
  });
}
