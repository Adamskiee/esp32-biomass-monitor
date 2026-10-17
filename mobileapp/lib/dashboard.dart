import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'features/safety/safety_threshold_editor.dart';
import 'features/safety/safety_thresholds.dart';
import 'features/safety/widgets/safety_threshold_group.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.apiService, this.onAlert});

  final ApiService apiService;
  final VoidCallback? onAlert;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  Map<String, dynamic> _state = {};
  List<String> _previousTriggers = [];
  bool _isMuted = false;
  bool? _queuedSprinklerState;
  bool _isPosting = false;
  bool _isFetching = false;
  bool _isOffline = false;
  String? _errorMessage;

  bool _thresholdsDirty = false;
  bool _isSavingThresholds = false;
  final SafetyThresholdEditor _thresholdEditor = SafetyThresholdEditor();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  void _startPolling() {
    _pollState();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (t) => _pollState());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopPolling();
    }
  }

  Future<void> _pollState() async {
    if (_isPosting || _isFetching) return;

    if (_queuedSprinklerState != null) {
      _isPosting = true;
      final toSend = _queuedSprinklerState!;
      try {
        await widget.apiService.setSprinkler(toSend);
        if (_queuedSprinklerState == toSend) {
          _queuedSprinklerState = null;
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            if (_queuedSprinklerState == toSend) {
              _queuedSprinklerState = null;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to set sprinkler: $e')),
          );
        }
      } finally {
        _isPosting = false;
      }
      return;
    }

    _isFetching = true;
    try {
      final state = await widget.apiService.fetchState();
      if (!mounted) return;
      final triggers = List<String>.from(state['active_triggers'] ?? []);
      _handleAlerts(triggers);
      setState(() {
        _state = state;
        _errorMessage = null;
        _isOffline = false;
        _previousTriggers = triggers;
        if (!_thresholdsDirty) {
          _thresholdEditor.refresh(SafetyThresholds.fromJson(state));
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOffline = true;
          _errorMessage = 'Failed to connect to ESP32: $e';
        });
      }
    } finally {
      _isFetching = false;
    }
  }

  void _handleAlerts(List<String> currentTriggers) {
    if (!mounted) return;
    if (currentTriggers.isNotEmpty) {
      final hasNew = currentTriggers.any((t) => !_previousTriggers.contains(t));
      if (hasNew && !_isMuted) {
        if (widget.onAlert != null) {
          widget.onAlert!();
        } else {
          SystemSound.play(SystemSoundType.alert);
        }
      }
      if (hasNew || currentTriggers.length != _previousTriggers.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('DANGER: ${currentTriggers.join(", ")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else if (currentTriggers.isEmpty && _previousTriggers.isNotEmpty) {
      _isMuted = false;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  Future<void> _saveThresholds() async {
    setState(() {
      _isSavingThresholds = true;
    });
    try {
      final errors = _thresholdEditor.validate();
      if (errors.isNotEmpty) {
        throw Exception(errors.values.first);
      }
      final changes = _thresholdEditor.changedValues();
      if (changes.isEmpty) return;
      final confirmed = await widget.apiService.updateSafetyThresholds(changes);
      if (!mounted) return;
      setState(() {
        _thresholdEditor.confirm(confirmed);
        _thresholdsDirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thresholds updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update thresholds: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingThresholds = false;
        });
      }
    }
  }

  String _formatParticulateReading(dynamic reading) {
    if (reading is! num) return '--';

    final value = reading.toDouble();
    final decimals = value == value.roundToDouble() ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} µg/m³';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    widget.apiService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state.isEmpty) {
      if (_errorMessage != null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Biomass Monitor')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(_errorMessage!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _pollState,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pumpOn = _state['pump_on'] is bool ? _state['pump_on'] as bool : null;
    final pumpLabel = pumpOn == true
        ? 'ACTIVE'
        : pumpOn == false
        ? 'IDLE'
        : 'UNAVAILABLE';
    final pumpColor = pumpOn == true
        ? Colors.blue
        : pumpOn == false
        ? Colors.grey
        : Colors.orange;
    final activeTriggers = List<String>.from(_state['active_triggers'] ?? []);
    final sprinklerLocked =
        activeTriggers.contains('high_chamber_temp') ||
        activeTriggers.contains('catastrophic_chamber_temp');
    SafetyThresholdField thresholdField(String key, String label) =>
        SafetyThresholdField(
          label: label,
          value: (_state[key] as num?)?.toString() ?? '',
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biomass Monitor Safety Dashboard'),
        actions: [
          if (_previousTriggers.isNotEmpty)
            IconButton(
              icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
              onPressed: () => setState(() => _isMuted = !_isMuted),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isOffline)
            Card(
              color: Colors.orange.shade100,
              child: const ListTile(
                leading: Icon(Icons.wifi_off),
                title: Text('ESP32 disconnected'),
                subtitle: Text(
                  'Last readings are stale. Controls are unavailable.',
                ),
              ),
            ),
          const Text(
            'Live Sensor Data',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.thermostat, color: Colors.orange),
                    title: const Text('Chamber Temperature'),
                    trailing: Text(
                      '${_state['chamber_temp_c'] ?? '--'} °C',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.water, color: pumpColor),
                    title: const Text('Pump Status'),
                    trailing: Text(
                      pumpLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: pumpColor,
                      ),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.air, color: Colors.blue),
                    title: const Text('MQ-2 Gas Sensor'),
                    trailing: Text(
                      '${_state['mq2_v'] ?? '--'} V',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Particulate Matter',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.grain, color: Colors.blueGrey),
                  title: Text(
                    'PM1.0: ${_formatParticulateReading(_state['pm1_0_ug_m3'] ?? _state['pm1_ug_m3'])}',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.grain, color: Colors.blueGrey),
                  title: Text(
                    'PM2.5: ${_formatParticulateReading(_state['pm2_5_ug_m3'] ?? _state['pm25_ug_m3'])}',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.grain, color: Colors.blueGrey),
                  title: Text(
                    'PM10: ${_formatParticulateReading(_state['pm10_ug_m3'])}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Manual Controls',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.water_drop_outlined),
              title: const Text('Manual Sprinkler'),
              subtitle: Text(
                _queuedSprinklerState == null
                    ? 'Reported by ESP32'
                    : 'Command pending; waiting for ESP32',
              ),
              value: pumpOn == true,
              onChanged:
                  _isOffline ||
                      sprinklerLocked ||
                      pumpOn == null ||
                      _queuedSprinklerState != null
                  ? null
                  : (val) => setState(() => _queuedSprinklerState = val),
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Safety Thresholds',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_state.containsKey('threshold_mq135_v')) ...[
            SafetyThresholdGroup(
              title: 'Temperature',
              currentReading: 'Chamber: ${_state['chamber_temp_c'] ?? '--'} °C',
              locked: _isOffline || _isSavingThresholds,
              fields: {
                'threshold_chamber_temp_c': thresholdField(
                  'threshold_chamber_temp_c',
                  'Chamber limit (°C)',
                ),
                'threshold_temperature_c': thresholdField(
                  'threshold_temperature_c',
                  'Ambient limit (°C)',
                ),
              },
              onChanged: _editThreshold,
            ),
            SafetyThresholdGroup(
              title: 'Gas',
              currentReading:
                  'MQ-2: ${_state['mq2_v'] ?? '--'} V, MQ-135: ${_state['mq135_v'] ?? '--'} V',
              locked: _isOffline || _isSavingThresholds,
              fields: {
                'threshold_mq2_v': thresholdField(
                  'threshold_mq2_v',
                  'MQ-2 limit (V)',
                ),
                'threshold_mq135_v': thresholdField(
                  'threshold_mq135_v',
                  'MQ-135 limit (V)',
                ),
              },
              onChanged: _editThreshold,
            ),
            SafetyThresholdGroup(
              title: 'Particulate matter',
              currentReading: 'PM2.5: ${_state['pm2_5_ug_m3'] ?? '--'} µg/m³',
              locked: _isOffline || _isSavingThresholds,
              fields: {
                'threshold_pm1_0_ug_m3': thresholdField(
                  'threshold_pm1_0_ug_m3',
                  'PM1.0 limit (µg/m³)',
                ),
                'threshold_pm2_5_ug_m3': thresholdField(
                  'threshold_pm2_5_ug_m3',
                  'PM2.5 limit (µg/m³)',
                ),
                'threshold_pm10_ug_m3': thresholdField(
                  'threshold_pm10_ug_m3',
                  'PM10 limit (µg/m³)',
                ),
              },
              onChanged: _editThreshold,
            ),
            SafetyThresholdGroup(
              title: 'Humidity',
              currentReading: 'Current: ${_state['humidity_percent'] ?? '--'}%',
              locked: _isOffline || _isSavingThresholds,
              fields: {
                'threshold_humidity_min_percent': thresholdField(
                  'threshold_humidity_min_percent',
                  'Minimum humidity (%)',
                ),
                'threshold_humidity_max_percent': thresholdField(
                  'threshold_humidity_max_percent',
                  'Maximum humidity (%)',
                ),
              },
              onChanged: _editThreshold,
            ),
            _thresholdSaveCard(),
          ] else
            const Card(
              child: ListTile(
                leading: Icon(Icons.system_update),
                title: Text('Firmware update required'),
                subtitle: Text(
                  'Install firmware with configurable safety thresholds to edit these limits.',
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _editThreshold(String field, String value) {
    setState(() {
      _thresholdEditor.edit(field, value);
      _thresholdsDirty = _thresholdEditor.hasDrafts;
    });
  }

  Widget _thresholdSaveCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Changes are applied only after the device confirms them.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isSavingThresholds
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Apply Thresholds'),
              onPressed: _isOffline || _isSavingThresholds || !_thresholdsDirty
                  ? null
                  : _saveThresholds,
            ),
          ),
        ],
      ),
    ),
  );
}
