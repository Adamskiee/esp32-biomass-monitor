class SafetyThresholds {
  const SafetyThresholds(this._values, this._supported);

  final Map<String, double?> _values;
  final Set<String> _supported;

  factory SafetyThresholds.fromJson(Map<String, dynamic> json) {
    const fields = <String>{
      'threshold_chamber_temp_c',
      'threshold_mq2_v',
      'threshold_mq135_v',
      'threshold_temperature_c',
      'threshold_pm1_0_ug_m3',
      'threshold_pm2_5_ug_m3',
      'threshold_pm10_ug_m3',
      'threshold_humidity_min_percent',
      'threshold_humidity_max_percent',
    };
    final supported = fields.where(json.containsKey).toSet();
    return SafetyThresholds({
      for (final field in supported)
        field: json[field] is num ? (json[field] as num).toDouble() : null,
    }, supported);
  }

  bool supports(String field) => _supported.contains(field);
  double? value(String field) => _values[field];
}
