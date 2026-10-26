import 'dart:async';

import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/core/widgets/icon_label.dart';
import 'package:biomass_iot_app/app/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api_service.dart';
import '../../../core/widgets/delayed_loading.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../monitoring/sensor_data.dart';
import '../safety_condition.dart';
import '../safety_observation_recorder.dart';
import '../safety_threshold_editor.dart';
import '../safety_thresholds.dart';
import 'safety_threshold_group.dart';

const _groups = <String, List<String>>{
  'Temperature': ['threshold_chamber_temp_c', 'threshold_temperature_c'],
  'Gas': ['threshold_mq2_v', 'threshold_mq135_v'],
  'Particulate Matter': [
    'threshold_pm1_0_ug_m3',
    'threshold_pm2_5_ug_m3',
    'threshold_pm10_ug_m3',
  ],
  'Humidity': [
    'threshold_humidity_min_percent',
    'threshold_humidity_max_percent',
  ],
};

const _faultNames = {
  'temp_sensor_fault': 'Chamber temperature sensor fault',
  'ambient_temp_sensor_fault': 'Ambient temperature sensor fault',
  'humidity_sensor_fault': 'Humidity sensor fault',
  'mq2_sensor_fault': 'MQ-2 sensor fault',
  'mq135_sensor_fault': 'MQ-135 sensor fault',
  'pms_sensor_fault': 'PMS5003 sensor fault',
};

class SafetyControlsPanel extends StatefulWidget {
  const SafetyControlsPanel({
    super.key,
    required this.apiService,
    this.observationRecorder,
    this.onAlert,
  });

  final ApiService apiService;
  final SafetyObservationRecorder? observationRecorder;
  final VoidCallback? onAlert;

  @override
  State<SafetyControlsPanel> createState() => _SafetyControlsPanelState();
}

class _SafetyControlsPanelState extends State<SafetyControlsPanel>
    with WidgetsBindingObserver {
  final _editor = SafetyThresholdEditor();
  final _thresholdGroupKeys = {
    for (final title in _groups.keys) title: GlobalKey(),
  };
  late final Map<String, TextEditingController> _controllers = {
    for (final field in _groups.values.expand((fields) => fields))
      field: TextEditingController(),
  };
  Timer? _timer;
  Map<String, dynamic>? _state;
  Set<String> _previousTriggers = {};
  bool _muted = false;
  bool _offline = false;
  bool _fetching = false;
  bool _posting = false;
  bool _saving = false;
  bool _foreground = true;
  bool? _queuedSprinkler;
  String? _error;
  int _settingsRevision = 0;
  String? _expandedThreshold;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  void _startPolling() {
    _timer?.cancel();
    unawaited(_poll());
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_poll()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _startPolling();
    } else {
      _timer?.cancel();
    }
  }

  void _syncInputs() {
    for (final entry in _controllers.entries) {
      final text = _editor.textFor(entry.key);
      if (entry.value.text != text) entry.value.text = text;
    }
  }

  Future<void> _poll() async {
    if (!mounted || !_foreground || _fetching || _posting || _saving) return;
    if (_queuedSprinkler != null) {
      setState(() => _posting = true);
      final desired = _queuedSprinkler!;
      try {
        await widget.apiService.setSprinkler(desired);
      } catch (error) {
        if (mounted) _message('Failed to set sprinkler: $error');
      } finally {
        if (mounted) {
          setState(() {
            _posting = false;
            if (_queuedSprinkler == desired) _queuedSprinkler = null;
          });
        }
      }
      if (!mounted) return;
    }
    _fetching = true;
    final revision = _settingsRevision;
    final ticket = widget.observationRecorder?.begin();
    try {
      final state = await widget.apiService.fetchState();
      if (!mounted || revision != _settingsRevision || _saving) return;
      if (ticket != null) {
        final accepted = await widget.observationRecorder!.accept(
          ticket,
          state,
        );
        if (!mounted || !accepted || revision != _settingsRevision || _saving) {
          return;
        }
      }
      final reading = SensorData.fromJson(state);
      final triggers = (state['active_triggers'] as List<dynamic>? ?? [])
          .whereType<String>()
          .where(
            (trigger) =>
                safetyConditionFor(trigger) != null ||
                _faultNames.containsKey(trigger),
          )
          .where((trigger) => !reading.isMqWarmingUp || !trigger.contains('mq'))
          .toSet();
      if (triggers.difference(_previousTriggers).isNotEmpty && !_muted) {
        if (widget.onAlert != null) {
          widget.onAlert!();
        } else {
          unawaited(SystemSound.play(SystemSoundType.alert));
        }
      }
      setState(() {
        _state = state;
        _offline = false;
        _error = null;
        if (triggers.isEmpty && _previousTriggers.isNotEmpty) _muted = false;
        _previousTriggers = triggers;
        _editor.refresh(SafetyThresholds.fromJson(state));
        _syncInputs();
      });
    } catch (error) {
      if (mounted && revision == _settingsRevision) {
        setState(() {
          _offline = true;
          _error = 'Failed to connect to ESP32: $error';
        });
      }
    } finally {
      _fetching = false;
      if (mounted && revision != _settingsRevision) unawaited(_poll());
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_offline || _saving || _posting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final errors = _editor.validate();
    if (errors.isNotEmpty) {
      final error = errors.entries.first;
      final field =
          error.key == 'humidity' || error.key.startsWith('threshold_humidity_')
          ? 'threshold_humidity_min_percent'
          : error.key;
      final group = _groups.entries
          .firstWhere((entry) => entry.value.contains(field))
          .key;
      setState(() => _expandedThreshold = field);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _thresholdGroupKeys[group]!.currentContext;
        if (target != null) unawaited(Scrollable.ensureVisible(target));
      });
      final label = error.key == 'humidity'
          ? 'Humidity'
          : SafetyThresholdGroup.labelFor(error.key);
      _message('$label: ${error.value}');
      return;
    }
    final changes = _editor.changedValues();
    if (changes.isEmpty) return;
    setState(() => _saving = true);
    try {
      final confirmed = await widget.apiService.updateSafetyThresholds(changes);
      if (!mounted) return;
      for (final field in changes.keys) {
        if (!confirmed.supports(field) || confirmed.value(field) == null) {
          throw StateError('Device did not confirm every submitted limit.');
        }
      }
      setState(() {
        _settingsRevision++;
        _expandedThreshold = null;
        _editor.confirm(
          SafetyThresholds.fromJson({
            for (final field in _controllers.keys)
              if (confirmed.supports(field))
                field: confirmed.value(field)
              else if (_editor.saved.supports(field))
                field: _editor.saved.value(field),
          }),
        );
        _syncInputs();
      });
      _message('Thresholds updated successfully');
    } catch (error) {
      if (mounted) _message('Failed to update thresholds: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        // Let a fetch begun before confirmation finish before requesting fresh state.
        if (!_fetching) unawaited(_poll());
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return DelayedLoading(
        isLoading: _error == null,
        placeholder: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Column(
            children: [
              LoadingSkeletonCard(height: 150),
              LoadingSkeletonCard(height: 180, margin: EdgeInsets.zero),
            ],
          ),
        ),
        child: Column(
          children: [
            if (_error != null) ...[
              Text(_error!),
              ElevatedButton(onPressed: _poll, child: const Text('Retry')),
            ],
          ],
        ),
      );
    }
    final reading = SensorData.fromJson(state);
    final triggers = _previousTriggers;
    final protection =
        triggers.contains('high_chamber_temp') ||
        triggers.contains('catastrophic_latch');
    final locked = _offline || _saving || _posting;
    final pump = state['pump_on'];
    final pumpLabel = pump == true
        ? 'ACTIVE'
        : pump == false
        ? 'IDLE'
        : 'UNAVAILABLE';
    final useLightColors = Theme.of(context).brightness == Brightness.light;
    final successColor = useLightColors
        ? AppTheme.successLight
        : AppTheme.neonGreen;
    final informationColor = useLightColors
        ? AppTheme.informationLight
        : AppTheme.neonBlue;
    final dangerColor = useLightColors
        ? AppTheme.dangerLight
        : AppTheme.neonRed;
    final alertColor = triggers.isEmpty ? successColor : dangerColor;
    final pumpColor = switch (pump) {
      true => successColor,
      false => informationColor,
      _ => dangerColor,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_offline)
          const Card(
            child: ListTile(
              leading: Icon(AppIcons.wifiDisconnected),
              title: Text('ESP32 disconnected'),
              subtitle: Text(
                'Last readings are stale. Controls are unavailable.',
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: IconLabel(
                        icon: AppIcons.alerts,
                        label: 'Active alerts',
                        color: alertColor,
                      ),
                    ),
                    IconButton(
                      tooltip: _muted ? 'Unmute app alerts' : 'Mute app alerts',
                      icon: Icon(_muted ? AppIcons.muted : AppIcons.volume),
                      onPressed: () => setState(() => _muted = !_muted),
                    ),
                  ],
                ),
                if (triggers.isEmpty) const Text('No active alerts'),
                for (final trigger in triggers)
                  Text(
                    safetyConditionFor(trigger)?.title ?? _faultNames[trigger]!,
                  ),
              ],
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(AppIcons.pump, color: pumpColor),
                title: const Text('Pump Status'),
                trailing: Text(
                  pumpLabel,
                  style: TextStyle(
                    color: pumpColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Reported relay output; water flow is not measured.',
                ),
              ),
              SwitchListTile(
                secondary: const Icon(AppIcons.sprinkler),
                title: const Text('Manual Sprinkler'),
                subtitle: Text(
                  protection
                      ? 'Chamber protection owns the pump.'
                      : 'Manual control available',
                ),
                value: _queuedSprinkler ?? pump == true,
                onChanged: _offline || _saving || protection || pump is! bool
                    ? null
                    : (value) {
                        setState(() => _queuedSprinkler = value);
                      },
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: IconLabel(
            icon: AppIcons.control,
            label: 'Safety Thresholds',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        for (final group in _groups.entries)
          SafetyThresholdGroup(
            key: _thresholdGroupKeys[group.key],
            title: group.key,
            icon: switch (group.key) {
              'Temperature' => AppIcons.ambientTemperature,
              'Gas' => AppIcons.gas,
              'Particulate Matter' => AppIcons.particulateMatter,
              'Humidity' => AppIcons.humidity,
              _ => AppIcons.control,
            },
            fields: group.value,
            editor: _editor,
            controllers: _controllers,
            reading: reading,
            activeTriggers: triggers,
            locked: locked,
            expandedField: _expandedThreshold,
            onToggle: (field) {
              FocusManager.instance.primaryFocus?.unfocus();
              setState(
                () => _expandedThreshold = _expandedThreshold == field
                    ? null
                    : field,
              );
            },
            onChanged: (field, value) =>
                setState(() => _editor.edit(field, value)),
          ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(AppIcons.apply),
          onPressed: locked || !_editor.isDirty ? null : _save,
          label: Text(_saving ? 'Saving thresholds...' : 'Apply Thresholds'),
        ),
      ],
    );
  }
}
