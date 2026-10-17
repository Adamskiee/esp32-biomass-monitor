import 'safety_thresholds.dart';

class SafetyThresholdEditor {
  SafetyThresholds _saved = const SafetyThresholds({}, {});
  final Map<String, String> _drafts = {};

  void refresh(SafetyThresholds saved) => _saved = saved;
  void edit(String field, String text) => _drafts[field] = text;
  bool get hasDrafts => _drafts.isNotEmpty;
  bool get isDirty => changedValues().isNotEmpty;

  Map<String, String> validate() {
    final errors = <String, String>{};
    for (final entry in _drafts.entries) {
      final value = double.tryParse(entry.value);
      if (value == null || !value.isFinite) {
        errors[entry.key] = 'Enter a finite number.';
      } else if (!_isWithinRange(entry.key, value)) {
        errors[entry.key] = _rangeError(entry.key);
      }
    }
    final min = _valueFor('threshold_humidity_min_percent');
    final max = _valueFor('threshold_humidity_max_percent');
    if ((min == null) != (max == null) &&
        (_drafts.containsKey('threshold_humidity_min_percent') ||
            _drafts.containsKey('threshold_humidity_max_percent'))) {
      errors['humidity'] = 'Set both humidity limits.';
    }
    if (min != null && max != null && min >= max) {
      errors['humidity'] = 'Maximum humidity must exceed minimum humidity.';
    }
    return errors;
  }

  double? _valueFor(String field) => _drafts.containsKey(field)
      ? double.tryParse(_drafts[field]!)
      : _saved.value(field);

  bool _isWithinRange(String field, double value) => switch (field) {
    'threshold_chamber_temp_c' => value >= 20 && value <= 150,
    'threshold_mq2_v' => value >= 0.1 && value <= 4.8,
    'threshold_mq135_v' => value >= 0.1 && value <= 5.0,
    'threshold_temperature_c' => value >= -40 && value <= 80,
    'threshold_pm1_0_ug_m3' ||
    'threshold_pm2_5_ug_m3' ||
    'threshold_pm10_ug_m3' => value > 0 && value <= 65535,
    'threshold_humidity_min_percent' ||
    'threshold_humidity_max_percent' => value >= 0 && value <= 100,
    _ => true,
  };

  String _rangeError(String field) => switch (field) {
    'threshold_chamber_temp_c' => 'Use a value from 20 to 150 °C.',
    'threshold_mq2_v' => 'Use a value from 0.1 to 4.8 V.',
    'threshold_mq135_v' => 'Use a value from 0.1 to 5.0 V.',
    'threshold_temperature_c' => 'Use a value from -40 to 80 °C.',
    'threshold_pm1_0_ug_m3' ||
    'threshold_pm2_5_ug_m3' ||
    'threshold_pm10_ug_m3' => 'Use a value above 0 µg/m³.',
    _ => 'Use a value from 0 to 100%.',
  };

  Map<String, double> changedValues() => {
    for (final entry in _drafts.entries)
      if (double.tryParse(entry.value) != null &&
          double.tryParse(entry.value) != _saved.value(entry.key))
        entry.key: double.parse(entry.value),
  };

  void confirm(SafetyThresholds saved) {
    _saved = saved;
    _drafts.clear();
  }
}
