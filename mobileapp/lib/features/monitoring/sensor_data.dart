class SensorData {
  final double? temperatureC, chamberTempC, mq135V, mq2V;
  final double? pm1_0UgM3, pm2_5UgM3, pm10UgM3;
  final DateTime timestamp;

  SensorData({
    this.temperatureC,
    this.chamberTempC,
    this.mq135V,
    this.mq2V,
    this.pm1_0UgM3,
    this.pm2_5UgM3,
    this.pm10UgM3,
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
    pm1_0UgM3: json['pm1_0_ug_m3'] != null
        ? (json['pm1_0_ug_m3'] as num).toDouble()
        : null,
    pm2_5UgM3: json['pm2_5_ug_m3'] != null
        ? (json['pm2_5_ug_m3'] as num).toDouble()
        : null,
    pm10UgM3: json['pm10_ug_m3'] != null
        ? (json['pm10_ug_m3'] as num).toDouble()
        : null,
    timestamp: DateTime.now(),
  );
}
