import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses complete environmental telemetry', () {
    final data = SensorData.fromJson({
      'temperature_c': 25,
      'chamber_temp_c': 45,
      'mq135_v': 1.2,
      'mq2_v': 1.0,
      'humidity_percent': 54.5,
      'pm1_ug_m3': 10,
      'pm25_ug_m3': 20,
      'pm10_ug_m3': 30,
    });

    expect(data.humidityPercent, 54.5);
    expect(data.pm1UgM3, 10.0);
    expect(data.pm25UgM3, 20.0);
    expect(data.pm10UgM3, 30.0);
  });

  test('preserves null environmental telemetry', () {
    final data = SensorData.fromJson({
      'temperature_c': 25,
      'chamber_temp_c': 45,
      'mq135_v': 1.2,
      'mq2_v': 1.0,
      'humidity_percent': null,
      'pm1_ug_m3': null,
      'pm25_ug_m3': null,
      'pm10_ug_m3': null,
    });

    expect(data.temperatureC, 25.0);
    expect(data.humidityPercent, isNull);
    expect(data.pm1UgM3, isNull);
    expect(data.pm25UgM3, isNull);
    expect(data.pm10UgM3, isNull);
  });
}
