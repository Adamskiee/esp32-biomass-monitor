import 'safety_thresholds.dart';

class SafetyThresholdEditor {
  SafetyThresholds _saved = const SafetyThresholds({}, {});
  final Map<String, String> _drafts = {};

  void refresh(SafetyThresholds saved) => _saved = saved;
  void edit(String field, String text) => _drafts[field] = text;
  bool get isDirty => changedValues().isNotEmpty;

  Map<String, String> validate() {
    final errors = <String, String>{};
    for (final entry in _drafts.entries) {
      final value = double.tryParse(entry.value);
      if (value == null || !value.isFinite) {
        errors[entry.key] = 'Enter a finite number.';
      }
    }
    final min = _drafts['threshold_humidity_min_percent'];
    final max = _drafts['threshold_humidity_max_percent'];
    if ((min == null) != (max == null)) {
      errors['humidity'] = 'Set both humidity limits.';
    }
    if (min != null &&
        max != null &&
        (double.tryParse(min) ?? 0) >= (double.tryParse(max) ?? 0)) {
      errors['humidity'] = 'Maximum humidity must exceed minimum humidity.';
    }
    return errors;
  }

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
