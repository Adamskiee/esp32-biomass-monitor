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

  test('parses the MQ warmup countdown from firmware', () {
    final reading = SensorData.fromJson({
      'mq_warming_up': true,
      'mq_warmup_remaining_seconds': 300,
      'mq135_v': null,
      'mq2_v': null,
    });

    expect(reading.isMqWarmingUp, isTrue);
    expect(reading.mqWarmupRemainingSeconds, 300);
  });

  test('parses humidity from the DHT22 firmware field', () {
    final reading = SensorData.fromJson({'humidity_percent': 54.5});

    expect(reading.humidityPercent, 54.5);
  });

  test('keeps MQ warmup active while firmware finishes the first reading', () {
    final reading = SensorData.fromJson({
      'mq_warming_up': true,
      'mq_warmup_remaining_seconds': 0,
    });

    expect(reading.isMqWarmingUp, isTrue);
  });
}
