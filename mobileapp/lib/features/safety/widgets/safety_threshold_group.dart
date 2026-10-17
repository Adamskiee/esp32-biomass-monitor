import 'package:flutter/material.dart';

import '../../monitoring/sensor_data.dart';
import '../safety_threshold_editor.dart';

class SafetyThresholdGroup extends StatelessWidget {
  const SafetyThresholdGroup({
    super.key,
    required this.title,
    required this.fields,
    required this.editor,
    required this.controllers,
    required this.reading,
    required this.activeTriggers,
    required this.locked,
    required this.onChanged,
  });
  final String title;
  final List<String> fields;
  final SafetyThresholdEditor editor;
  final Map<String, TextEditingController> controllers;
  final SensorData reading;
  final Set<String> activeTriggers;
  final bool locked;
  final void Function(String field, String value) onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          for (final field in fields)
            _ThresholdRow(
              definition: _definitions[field]!,
              editor: editor,
              controller: controllers[field]!,
              reading: reading,
              activeTriggers: activeTriggers,
              locked: locked,
              onChanged: onChanged,
            ),
        ],
      ),
    ),
  );
}

class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({
    required this.definition,
    required this.editor,
    required this.controller,
    required this.reading,
    required this.activeTriggers,
    required this.locked,
    required this.onChanged,
  });
  final _FieldDefinition definition;
  final SafetyThresholdEditor editor;
  final TextEditingController controller;
  final SensorData reading;
  final Set<String> activeTriggers;
  final bool locked;
  final void Function(String field, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    final supported = editor.saved.supports(definition.field);
    final saved = editor.saved.value(definition.field);
    final errors = editor.validate();
    final error = errors[definition.field] ?? errors['humidity'];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(definition.label, style: Theme.of(context).textTheme.titleSmall),
          Text(
            'Current: ${_format(definition.reading(reading), definition.unit)}',
          ),
          Text(
            saved == null
                ? 'Saved limit: Not configured'
                : 'Saved limit: ${_format(saved, definition.unit)}',
          ),
          Text(definition.actionLabel),
          Text(_status(supported, saved)),
          if (definition.field == 'threshold_mq2_v')
            const Text('New limits cannot exceed 4.8 V.'),
          TextFormField(
            key: ValueKey(definition.field),
            controller: controller,
            enabled: supported && !locked,
            onChanged: (value) => onChanged(definition.field, value),
            keyboardType: TextInputType.numberWithOptions(
              decimal: true,
              signed: definition.field == 'threshold_temperature_c',
            ),
            decoration: InputDecoration(
              labelText: 'Limit (${definition.unit})',
              helperText: supported ? null : 'Firmware update required',
              errorText: error,
            ),
          ),
        ],
      ),
    );
  }

  String _status(bool supported, double? saved) {
    if (!supported) return 'Firmware update required';
    if (definition.isMq && reading.isMqWarmingUp)
      return 'Warming up: ${reading.mqWarmupRemainingSeconds} s';
    if (activeTriggers.contains(definition.faultTrigger) ||
        definition.reading(reading) == null)
      return 'Sensor fault';
    if (activeTriggers.any(definition.alertTriggers.contains)) return 'Alert';
    if (saved == null) return 'Not configured';
    return 'Normal';
  }
}

String _format(double? value, String unit) {
  if (value == null) return '--';
  final display = value == value.truncateToDouble()
      ? value.truncate().toString()
      : value.toString();
  return '$display $unit';
}

class _FieldDefinition {
  const _FieldDefinition({
    required this.field,
    required this.label,
    required this.unit,
    required this.actionLabel,
    required this.reading,
    required this.alertTriggers,
    required this.faultTrigger,
    this.isMq = false,
  });
  final String field;
  final String label;
  final String unit;
  final String actionLabel;
  final double? Function(SensorData) reading;
  final Set<String> alertTriggers;
  final String faultTrigger;
  final bool isMq;
}

const _definitions = <String, _FieldDefinition>{
  'threshold_chamber_temp_c': _FieldDefinition(
    field: 'threshold_chamber_temp_c',
    label: 'Chamber temperature',
    unit: '°C',
    actionLabel: 'Alerts + automatic sprinkler',
    reading: _chamber,
    alertTriggers: {'high_chamber_temp', 'catastrophic_latch'},
    faultTrigger: 'temp_sensor_fault',
  ),
  'threshold_temperature_c': _FieldDefinition(
    field: 'threshold_temperature_c',
    label: 'Ambient temperature',
    unit: '°C',
    actionLabel: 'Alerts only',
    reading: _ambient,
    alertTriggers: {'high_ambient_temp'},
    faultTrigger: 'ambient_temp_sensor_fault',
  ),
  'threshold_mq2_v': _FieldDefinition(
    field: 'threshold_mq2_v',
    label: 'MQ-2',
    unit: 'V',
    actionLabel: 'Alerts only',
    reading: _mq2,
    alertTriggers: {'high_mq2_gas'},
    faultTrigger: 'mq2_sensor_fault',
    isMq: true,
  ),
  'threshold_mq135_v': _FieldDefinition(
    field: 'threshold_mq135_v',
    label: 'MQ-135',
    unit: 'V',
    actionLabel: 'Alerts only',
    reading: _mq135,
    alertTriggers: {'high_mq135_gas'},
    faultTrigger: 'mq135_sensor_fault',
    isMq: true,
  ),
  'threshold_pm1_0_ug_m3': _FieldDefinition(
    field: 'threshold_pm1_0_ug_m3',
    label: 'PM1.0',
    unit: 'µg/m³',
    actionLabel: 'Alerts only',
    reading: _pm1,
    alertTriggers: {'high_pm1_0'},
    faultTrigger: 'pms_sensor_fault',
  ),
  'threshold_pm2_5_ug_m3': _FieldDefinition(
    field: 'threshold_pm2_5_ug_m3',
    label: 'PM2.5',
    unit: 'µg/m³',
    actionLabel: 'Alerts only',
    reading: _pm25,
    alertTriggers: {'high_pm2_5'},
    faultTrigger: 'pms_sensor_fault',
  ),
  'threshold_pm10_ug_m3': _FieldDefinition(
    field: 'threshold_pm10_ug_m3',
    label: 'PM10',
    unit: 'µg/m³',
    actionLabel: 'Alerts only',
    reading: _pm10,
    alertTriggers: {'high_pm10'},
    faultTrigger: 'pms_sensor_fault',
  ),
  'threshold_humidity_min_percent': _FieldDefinition(
    field: 'threshold_humidity_min_percent',
    label: 'Humidity minimum',
    unit: '%',
    actionLabel: 'Alerts only',
    reading: _humidity,
    alertTriggers: {'low_humidity'},
    faultTrigger: 'humidity_sensor_fault',
  ),
  'threshold_humidity_max_percent': _FieldDefinition(
    field: 'threshold_humidity_max_percent',
    label: 'Humidity maximum',
    unit: '%',
    actionLabel: 'Alerts only',
    reading: _humidity,
    alertTriggers: {'high_humidity'},
    faultTrigger: 'humidity_sensor_fault',
  ),
};

double? _chamber(SensorData data) => data.chamberTempC;
double? _ambient(SensorData data) => data.temperatureC;
double? _mq2(SensorData data) => data.mq2V;
double? _mq135(SensorData data) => data.mq135V;
double? _pm1(SensorData data) => data.pm1_0UgM3;
double? _pm25(SensorData data) => data.pm2_5UgM3;
double? _pm10(SensorData data) => data.pm10UgM3;
double? _humidity(SensorData data) => data.humidityPercent;
