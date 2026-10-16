import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';

class SafetyCondition {
  const SafetyCondition({
    required this.trigger,
    required this.title,
    required this.severity,
    required this.describe,
  });

  final String trigger;
  final String title;
  final String severity;
  final String Function(SensorData reading) describe;
}

String _value(double? value, String unit) => value == null
    ? 'Reading unavailable.'
    : 'Reported reading: ${value.toStringAsFixed(1)} $unit.';

SafetyCondition? safetyConditionFor(String trigger) {
  const conditions = <String, SafetyCondition>{
    'high_chamber_temp': SafetyCondition(
      trigger: 'high_chamber_temp',
      title: 'High Chamber Temperature',
      severity: 'critical',
      describe: _chamber,
    ),
    'catastrophic_latch': SafetyCondition(
      trigger: 'catastrophic_latch',
      title: 'Catastrophic Chamber Temperature',
      severity: 'critical',
      describe: _chamber,
    ),
    'high_mq2_gas': SafetyCondition(
      trigger: 'high_mq2_gas',
      title: 'High MQ-2 Gas Reading',
      severity: 'critical',
      describe: _mq2,
    ),
    'high_mq135_gas': SafetyCondition(
      trigger: 'high_mq135_gas',
      title: 'High MQ-135 Gas Reading',
      severity: 'warning',
      describe: _mq135,
    ),
    'high_ambient_temp': SafetyCondition(
      trigger: 'high_ambient_temp',
      title: 'High Ambient Temperature',
      severity: 'warning',
      describe: _temperature,
    ),
    'high_pm1_0': SafetyCondition(
      trigger: 'high_pm1_0',
      title: 'High PM1.0',
      severity: 'warning',
      describe: _pm1,
    ),
    'high_pm2_5': SafetyCondition(
      trigger: 'high_pm2_5',
      title: 'High PM2.5',
      severity: 'warning',
      describe: _pm25,
    ),
    'high_pm10': SafetyCondition(
      trigger: 'high_pm10',
      title: 'High PM10',
      severity: 'warning',
      describe: _pm10,
    ),
    'low_humidity': SafetyCondition(
      trigger: 'low_humidity',
      title: 'Low Humidity',
      severity: 'warning',
      describe: _humidity,
    ),
    'high_humidity': SafetyCondition(
      trigger: 'high_humidity',
      title: 'High Humidity',
      severity: 'warning',
      describe: _humidity,
    ),
  };
  return conditions[trigger];
}

String _chamber(SensorData reading) => _value(reading.chamberTempC, '°C');
String _mq2(SensorData reading) => _value(reading.mq2V, 'V');
String _mq135(SensorData reading) => _value(reading.mq135V, 'V');
String _temperature(SensorData reading) => _value(reading.temperatureC, '°C');
String _pm1(SensorData reading) => _value(reading.pm1_0UgM3, 'µg/m³');
String _pm25(SensorData reading) => _value(reading.pm2_5UgM3, 'µg/m³');
String _pm10(SensorData reading) => _value(reading.pm10UgM3, 'µg/m³');
String _humidity(SensorData reading) => _value(reading.humidityPercent, '%');
