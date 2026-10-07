class SensorData {
  final double? temperatureC, chamberTempC, mq135V, mq2V;
  final DateTime timestamp;

  SensorData({
    this.temperatureC,
    this.chamberTempC,
    this.mq135V,
    this.mq2V,
    required this.timestamp,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) => SensorData(
    temperatureC: json['temperature_c'] != null
        ? (json['temperature_c'] as num).toDouble()
        : null,
    chamberTempC: json['chamber_temp_c'] != null
        ? (json['chamber_temp_c'] as num).toDouble()
        : null,
    mq135V: json['mq135_v'] != null
        ? (json['mq135_v'] as num).toDouble()
        : null,
    mq2V: json['mq2_v'] != null ? (json['mq2_v'] as num).toDouble() : null,
    timestamp: DateTime.now(),
  );
}
