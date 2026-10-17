class SensorData {
  final double? temperatureC, humidityPercent, chamberTempC, mq135V, mq2V;
  final double? pm1_0UgM3, pm2_5UgM3, pm10UgM3;
  final int mqWarmupRemainingSeconds;
  final bool mqWarmingUp;
  final DateTime timestamp;
  final Set<String> _reportedFields;

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
    this.mqWarmupRemainingSeconds = 0,
    this.mqWarmingUp = false,
    Set<String> reportedFields = const {},
    required this.timestamp,
  }) : pm1_0UgM3 = pm1_0UgM3 ?? pm1UgM3,
       pm2_5UgM3 = pm2_5UgM3 ?? pm25UgM3,
       _reportedFields = reportedFields;

  bool get isMqWarmingUp => mqWarmingUp;

  double? get pm1UgM3 => pm1_0UgM3;
  double? get pm25UgM3 => pm2_5UgM3;

  bool reportsField(String field) => _reportedFields.contains(field);

  factory SensorData.fromJson(Map<String, dynamic> json) => SensorData(
    temperatureC: _number(json['temperature_c']),
    humidityPercent: _number(json['humidity_percent']),
    chamberTempC: _number(json['chamber_temp_c']),
    mq135V: _number(json['mq135_v']),
    mq2V: _number(json['mq2_v']),
    mqWarmupRemainingSeconds:
        (json['mq_warmup_remaining_seconds'] as num?)?.toInt() ?? 0,
    mqWarmingUp: json['mq_warming_up'] == true,
    pm1_0UgM3: _number(json['pm1_0_ug_m3'] ?? json['pm1_ug_m3']),
    pm2_5UgM3: _number(json['pm2_5_ug_m3'] ?? json['pm25_ug_m3']),
    pm10UgM3: _number(json['pm10_ug_m3']),
    reportedFields: json.keys.toSet(),
    timestamp: DateTime.now(),
  );
}

double? _number(dynamic value) =>
    value is num && value.isFinite ? value.toDouble() : null;
