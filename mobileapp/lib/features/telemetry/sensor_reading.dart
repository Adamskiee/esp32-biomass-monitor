class SensorReading {
  const SensorReading({
    required this.timestamp,
    this.temperatureC,
    this.chamberTempC,
    this.mq135V,
    this.mq2V,
  });

  final double? temperatureC;
  final double? chamberTempC;
  final double? mq135V;
  final double? mq2V;
  final DateTime timestamp;

  factory SensorReading.fromJson(
    Map<String, dynamic> json,
    DateTime timestamp,
  ) {
    double? valueFor(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! num) throw FormatException('$key must be numeric');
      return value.toDouble();
    }

    return SensorReading(
      timestamp: timestamp,
      temperatureC: valueFor('temperature_c'),
      chamberTempC: valueFor('chamber_temp_c'),
      mq135V: valueFor('mq135_v'),
      mq2V: valueFor('mq2_v'),
    );
  }
}
