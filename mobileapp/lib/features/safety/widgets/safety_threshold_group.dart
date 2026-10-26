import 'package:biomass_iot_app/core/widgets/icon_label.dart';
import 'package:biomass_iot_app/app/app_icons.dart';
import 'package:flutter/material.dart';

import '../../monitoring/sensor_data.dart';
import '../safety_threshold_editor.dart';
import 'safety_threshold_sliders.dart';

class SafetyThresholdGroup extends StatelessWidget {
  static String labelFor(String field) => _definitions[field]!.label;

  const SafetyThresholdGroup({
    super.key,
    required this.title,
    this.icon = AppIcons.control,
    this.color,
    required this.fields,
    required this.editor,
    required this.controllers,
    required this.reading,
    required this.activeTriggers,
    required this.locked,
    required this.expandedField,
    required this.onToggle,
    required this.onChanged,
  });
  final String title;
  final IconData icon;
  final Color? color;
  final List<String> fields;
  final SafetyThresholdEditor editor;
  final Map<String, TextEditingController> controllers;
  final SensorData reading;
  final Set<String> activeTriggers;
  final bool locked;
  final String? expandedField;
  final ValueChanged<String> onToggle;
  final void Function(String field, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    final humidityPair =
        fields.contains(_humidityMin) && fields.contains(_humidityMax);
    final alertsOnly = fields.every(
      (field) => _definitions[field]!.actionLabel == 'Alerts only',
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!humidityPair) ...[
              IconLabel(
                icon: icon,
                label: title,
                style: Theme.of(context).textTheme.titleMedium,
                color: color,
              ),
              if (alertsOnly)
                Text('Alerts only', style: _secondaryStyle(context)),
            ],
            if (humidityPair)
              _HumidityThresholdRow(
                editor: editor,
                controllers: controllers,
                reading: reading,
                activeTriggers: activeTriggers,
                locked: locked,
                expanded: expandedField == _humidityMin,
                onToggle: () => onToggle(_humidityMin),
                onChanged: onChanged,
                color: color,
              ),
            for (final field in fields)
              if (!humidityPair || !_definitions[field]!.isHumidity) ...[
                if (field != fields.first) const Divider(height: 16),
                _ThresholdRow(
                  definition: _definitions[field]!,
                  editor: editor,
                  controller: controllers[field]!,
                  reading: reading,
                  activeTriggers: activeTriggers,
                  locked: locked,
                  expanded: expandedField == field,
                  onToggle: () => onToggle(field),
                  showAction: !alertsOnly,
                  onChanged: onChanged,
                  color: color,
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({
    required this.definition,
    required this.editor,
    required this.controller,
    required this.reading,
    required this.activeTriggers,
    required this.locked,
    required this.expanded,
    required this.onToggle,
    required this.showAction,
    required this.onChanged,
    this.color,
  });
  final _FieldDefinition definition;
  final SafetyThresholdEditor editor;
  final TextEditingController controller;
  final SensorData reading;
  final Set<String> activeTriggers;
  final bool locked;
  final bool expanded;
  final VoidCallback onToggle;
  final bool showAction;
  final void Function(String field, String value) onChanged;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final supported = editor.saved.supports(definition.field);
    final saved = editor.saved.value(definition.field);
    late final error = editor.validate()[definition.field];
    late final input = _LimitInput(
      definition: definition,
      controller: controller,
      enabled: supported && !locked && expanded,
      onChanged: onChanged,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SensorHeader(
          key: ValueKey('${definition.field}_header'),
          title: definition.label,
          icon: definition.icon,
          color:
              _status(definition, editor, reading, activeTriggers) == 'Normal'
              ? color
              : Theme.of(context).colorScheme.error,
          status: _status(definition, editor, reading, activeTriggers),
          details: [
            if (expanded)
              'Current: ${_format(definition.reading(reading), definition.unit)}',
          ],
          action: showAction
              ? Row(
                  children: [
                    if (definition.field == 'threshold_chamber_temp_c') ...[
                      Icon(
                        AppIcons.safety,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        definition.actionLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                )
              : null,
          expanded: expanded,
          onToggle: onToggle,
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (definition.isHumidity)
                  input
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final slider = SafetyThresholdSlider(
                        key: ValueKey('${definition.field}_slider_control'),
                        field: definition.field,
                        label: definition.label,
                        unit: definition.unit,
                        controller: controller,
                        saved: saved,
                        minimum: definition.minimum,
                        maximum: definition.maximum,
                        step: definition.step,
                        expandRange: definition.isParticulate,
                        enabled: supported && !locked && expanded,
                        onDefault: () => _restoreDefault(
                          definition.field,
                          controller,
                          onChanged,
                        ),
                        onChanged: (value) =>
                            onChanged(definition.field, value),
                      );
                      if (constraints.maxWidth <
                          360 * MediaQuery.textScalerOf(context).scale(1)) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [slider, const SizedBox(height: 16), input],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: slider),
                          const SizedBox(width: 16),
                          SizedBox(width: 128, child: input),
                        ],
                      );
                    },
                  ),
                if (error != null) _ValidationMessage(error),
                if (definition.field == 'threshold_mq2_v')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'New limits cannot exceed 4.8 V.',
                      style: _secondaryStyle(context),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

const _humidityMin = 'threshold_humidity_min_percent';
const _humidityMax = 'threshold_humidity_max_percent';

class _HumidityThresholdRow extends StatelessWidget {
  const _HumidityThresholdRow({
    required this.editor,
    required this.controllers,
    required this.reading,
    required this.activeTriggers,
    required this.locked,
    required this.expanded,
    required this.onToggle,
    required this.onChanged,
    this.color,
  });

  final SafetyThresholdEditor editor;
  final Map<String, TextEditingController> controllers;
  final SensorData reading;
  final Set<String> activeTriggers;
  final bool locked;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(String field, String value) onChanged;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final statuses = [
      for (final field in [_humidityMin, _humidityMax])
        _status(_definitions[field]!, editor, reading, activeTriggers),
    ];
    final status = statuses.contains('Sensor fault')
        ? 'Sensor fault'
        : statuses.contains('Alert')
        ? 'Alert'
        : statuses.contains('Firmware update required')
        ? 'Firmware update required'
        : statuses.contains('Not configured')
        ? 'Not configured'
        : 'Normal';
    late final errors = editor.validate();
    Widget input(String field, String label) => _LimitInput(
      definition: _definitions[field]!,
      controller: controllers[field]!,
      label: label,
      enabled: !locked && expanded && editor.saved.supports(field),
      error: errors[field],
      helper:
          !editor.saved.supports(field) && status != 'Firmware update required'
          ? 'Firmware update required'
          : null,
      onChanged: onChanged,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SensorHeader(
          key: const ValueKey('humidity_range_header'),
          title: 'Humidity',
          icon: AppIcons.humidity,
          color: status == 'Normal'
              ? color
              : Theme.of(context).colorScheme.error,
          status: status,
          details: [
            if (expanded) 'Current: ${_format(reading.humidityPercent, '%')}',
            'Alerts only',
          ],
          expanded: expanded,
          onToggle: onToggle,
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final minimum = input(_humidityMin, 'Minimum');
                    final maximum = input(_humidityMax, 'Maximum');
                    if (constraints.maxWidth <
                        280 * MediaQuery.textScalerOf(context).scale(1)) {
                      return Column(
                        children: [
                          minimum,
                          const SizedBox(height: 16),
                          maximum,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: minimum),
                        const SizedBox(width: 16),
                        Expanded(child: maximum),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                SafetyHumidityRangeSlider(
                  minimumController: controllers[_humidityMin]!,
                  maximumController: controllers[_humidityMax]!,
                  enabled:
                      !locked &&
                      expanded &&
                      editor.saved.supports(_humidityMin) &&
                      editor.saved.supports(_humidityMax),
                  onDefault: () {
                    _restoreDefault(
                      _humidityMin,
                      controllers[_humidityMin]!,
                      onChanged,
                    );
                    _restoreDefault(
                      _humidityMax,
                      controllers[_humidityMax]!,
                      onChanged,
                    );
                  },
                  onChanged: onChanged,
                ),

                if (errors['humidity'] case final error?)
                  _ValidationMessage(error),
              ],
            ),
          ),
      ],
    );
  }
}

class _SensorHeader extends StatelessWidget {
  const _SensorHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.status,
    required this.details,
    required this.expanded,
    required this.onToggle,
    this.color,
    this.action,
  });

  final String title;
  final IconData icon;
  final String status;
  final List<String> details;
  final bool expanded;
  final VoidCallback onToggle;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: expanded,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ThresholdSummary(
                    title: title,
                    status: status,
                    details: details,
                  ),
                  if (action != null) ...[const SizedBox(height: 8), action!],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(expanded ? AppIcons.collapse : AppIcons.expand),
          ],
        ),
      ),
    ),
  );
}

class _LimitInput extends StatelessWidget {
  const _LimitInput({
    required this.definition,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.label = 'Limit',
    this.error,
    this.helper,
  });

  final _FieldDefinition definition;
  final TextEditingController controller;
  final bool enabled;
  final void Function(String field, String value) onChanged;
  final String label;
  final String? error;
  final String? helper;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey(definition.field),
    controller: controller,
    enabled: enabled,
    onChanged: (value) => onChanged(definition.field, value),
    keyboardType: TextInputType.numberWithOptions(
      decimal: true,
      signed: definition.field == 'threshold_temperature_c',
    ),
    decoration: InputDecoration(
      labelText: label,
      suffixText: definition.unit,
      border: const OutlineInputBorder(),
      errorText: error,
      errorMaxLines: 3,
      helperText: helper,
      helperMaxLines: 3,
    ),
  );
}

class _ThresholdSummary extends StatelessWidget {
  const _ThresholdSummary({
    this.title,
    required this.status,
    required this.details,
  });

  final String? title;
  final String status;
  final List<String> details;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (title != null || status != 'Normal') ...[
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (title != null)
              Text(title!, style: Theme.of(context).textTheme.titleSmall),
            if (status != 'Normal') _StatusBadge(status),
          ],
        ),
      ],
      if (details.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final detail in details)
              Text(detail, style: _secondaryStyle(context)),
          ],
        ),
      ],
    ],
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (status) {
      'Alert' || 'Sensor fault' => colors.error,
      _ => colors.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _ValidationMessage extends StatelessWidget {
  const _ValidationMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.error,
      ),
    ),
  );
}

TextStyle? _secondaryStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall
    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

String _status(
  _FieldDefinition definition,
  SafetyThresholdEditor editor,
  SensorData reading,
  Set<String> activeTriggers,
) {
  if (!editor.saved.supports(definition.field)) {
    return 'Firmware update required';
  }
  if (definition.isMq && reading.isMqWarmingUp) {
    return 'Warming up: ${reading.mqWarmupRemainingSeconds} s';
  }
  if (activeTriggers.contains(definition.faultTrigger) ||
      definition.reading(reading) == null) {
    return 'Sensor fault';
  }
  if (activeTriggers.any(definition.alertTriggers.contains)) return 'Alert';
  if (editor.saved.value(definition.field) == null) return 'Not configured';
  return 'Normal';
}

void _restoreDefault(
  String field,
  TextEditingController controller,
  void Function(String field, String value) onChanged,
) {
  final text = _format(_definitions[field]!.defaultValue);
  controller.text = text;
  onChanged(field, text);
}

String _format(double? value, [String unit = '']) {
  if (value == null) return '--';
  final display = value == value.truncateToDouble()
      ? value.truncate().toString()
      : value.toString();
  return unit.isEmpty ? display : '$display $unit';
}

class _FieldDefinition {
  const _FieldDefinition({
    required this.field,
    required this.label,
    required this.icon,
    required this.unit,
    required this.defaultValue,
    required this.actionLabel,
    required this.reading,
    required this.alertTriggers,
    required this.faultTrigger,
    this.isMq = false,
  });
  final String field;
  final String label;
  final IconData icon;
  final String unit;
  final double defaultValue;
  final String actionLabel;
  final double? Function(SensorData) reading;
  final Set<String> alertTriggers;
  final String faultTrigger;
  final bool isMq;

  bool get isHumidity => field.startsWith('threshold_humidity_');
  bool get isParticulate => field.startsWith('threshold_pm');

  double get minimum => switch (field) {
    'threshold_chamber_temp_c' => 20,
    'threshold_temperature_c' => -40,
    'threshold_mq2_v' || 'threshold_mq135_v' => 0.1,
    _ => 1,
  };

  double get maximum => switch (field) {
    'threshold_chamber_temp_c' => 150,
    'threshold_temperature_c' => 80,
    'threshold_mq2_v' => 4.8,
    'threshold_mq135_v' => 5,
    _ => 65535,
  };

  double get step => isMq
      ? 0.1
      : isParticulate
      ? 1
      : 0.5;
}

const _definitions = <String, _FieldDefinition>{
  'threshold_chamber_temp_c': _FieldDefinition(
    field: 'threshold_chamber_temp_c',
    defaultValue: 80,
    label: 'Chamber temperature',
    icon: AppIcons.chamberTemperature,
    unit: '°C',
    actionLabel: 'Alerts + automatic sprinkler',
    reading: _chamber,
    alertTriggers: {'high_chamber_temp', 'catastrophic_latch'},
    faultTrigger: 'temp_sensor_fault',
  ),
  'threshold_temperature_c': _FieldDefinition(
    field: 'threshold_temperature_c',
    defaultValue: 35,
    label: 'Ambient temperature',
    icon: AppIcons.ambientTemperature,
    unit: '°C',
    actionLabel: 'Alerts only',
    reading: _ambient,
    alertTriggers: {'high_ambient_temp'},
    faultTrigger: 'ambient_temp_sensor_fault',
  ),
  'threshold_mq2_v': _FieldDefinition(
    field: 'threshold_mq2_v',
    defaultValue: 2.5,
    label: 'MQ-2',
    icon: AppIcons.smoke,
    unit: 'V',
    actionLabel: 'Alerts only',
    reading: _mq2,
    alertTriggers: {'high_mq2_gas'},
    faultTrigger: 'mq2_sensor_fault',
    isMq: true,
  ),
  'threshold_mq135_v': _FieldDefinition(
    field: 'threshold_mq135_v',
    defaultValue: 2,
    label: 'MQ-135',
    icon: AppIcons.gas,
    unit: 'V',
    actionLabel: 'Alerts only',
    reading: _mq135,
    alertTriggers: {'high_mq135_gas'},
    faultTrigger: 'mq135_sensor_fault',
    isMq: true,
  ),
  'threshold_pm1_0_ug_m3': _FieldDefinition(
    field: 'threshold_pm1_0_ug_m3',
    defaultValue: 15,
    label: 'PM1.0',
    icon: AppIcons.particulateMatter,
    unit: 'µg/m³',
    actionLabel: 'Alerts only',
    reading: _pm1,
    alertTriggers: {'high_pm1_0'},
    faultTrigger: 'pms_sensor_fault',
  ),
  'threshold_pm2_5_ug_m3': _FieldDefinition(
    field: 'threshold_pm2_5_ug_m3',
    defaultValue: 15,
    label: 'PM2.5',
    icon: AppIcons.particulateMatter,
    unit: 'µg/m³',
    actionLabel: 'Alerts only',
    reading: _pm25,
    alertTriggers: {'high_pm2_5'},
    faultTrigger: 'pms_sensor_fault',
  ),
  'threshold_pm10_ug_m3': _FieldDefinition(
    field: 'threshold_pm10_ug_m3',
    defaultValue: 45,
    label: 'PM10',
    icon: AppIcons.particulateMatter,
    unit: 'µg/m³',
    actionLabel: 'Alerts only',
    reading: _pm10,
    alertTriggers: {'high_pm10'},
    faultTrigger: 'pms_sensor_fault',
  ),
  'threshold_humidity_min_percent': _FieldDefinition(
    field: 'threshold_humidity_min_percent',
    defaultValue: 30,
    label: 'Humidity minimum',
    icon: AppIcons.humidity,
    unit: '%',
    actionLabel: 'Alerts only',
    reading: _humidity,
    alertTriggers: {'low_humidity'},
    faultTrigger: 'humidity_sensor_fault',
  ),
  'threshold_humidity_max_percent': _FieldDefinition(
    field: 'threshold_humidity_max_percent',
    defaultValue: 60,
    label: 'Humidity maximum',
    icon: AppIcons.humidity,
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
