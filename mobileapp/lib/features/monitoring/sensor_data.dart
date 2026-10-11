class SensorData {
  final double? temperatureC, humidityPercent, chamberTempC, mq135V, mq2V;
  final double? pm1_0UgM3, pm2_5UgM3, pm10UgM3;
  final DateTime timestamp;

  SensorData({
    this.temperatureC,
    this.humidityPercent,
    this.chamberTempC,
    this.mq135V,
    this.mq2V,
    double? pm1_0UgM3,
    double? pm2_5UgM3,
    double? pm1UgM3,
    double? pm25UgM3,
    this.pm10UgM3,
    required this.timestamp,
  }) : pm1_0UgM3 = pm1_0UgM3 ?? pm1UgM3,
       pm2_5UgM3 = pm2_5UgM3 ?? pm25UgM3;

  double? get pm1UgM3 => pm1_0UgM3;
  double? get pm25UgM3 => pm2_5UgM3;

  factory SensorData.fromJson(Map<String, dynamic> json) => SensorData(
    temperatureC: json['temperature_c'] != null
        ? (json['temperature_c'] as num).toDouble()
        : null,
    humidityPercent: json['humidity_percent'] != null
        ? (json['humidity_percent'] as num).toDouble()
        : null,
    chamberTempC: json['chamber_temp_c'] != null
        ? (json['chamber_temp_c'] as num).toDouble()
        : null,
    mq135V: json['mq135_v'] != null
        ? (json['mq135_v'] as num).toDouble()
        : null,
    mq2V: json['mq2_v'] != null ? (json['mq2_v'] as num).toDouble() : null,
    pm1_0UgM3: (json['pm1_0_ug_m3'] ?? json['pm1_ug_m3']) != null
        ? ((json['pm1_0_ug_m3'] ?? json['pm1_ug_m3']) as num).toDouble()
        : null,
    pm2_5UgM3: (json['pm2_5_ug_m3'] ?? json['pm25_ug_m3']) != null
        ? ((json['pm2_5_ug_m3'] ?? json['pm25_ug_m3']) as num).toDouble()
        : null,
    pm10UgM3: json['pm10_ug_m3'] != null
        ? (json['pm10_ug_m3'] as num).toDouble()
        : null,
    timestamp: DateTime.now(),
  );
}
