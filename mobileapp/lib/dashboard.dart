import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

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
  String? _errorMessage;

  double _tempLimit = 60.0;
  double _mq2Limit = 1.5;
  bool _thresholdsInitialized = false;
  bool _isSavingThresholds = false;

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
        await ApiService.setSprinkler(toSend);
        if (_queuedSprinklerState == toSend) {
          _queuedSprinklerState = null;
        }
      } catch (e) {
        // Ignore transient network errors during debounced post
      } finally {
        _isPosting = false;
      }
      return;
    }

    _isFetching = true;
    try {
      final state = await ApiService.fetchState();
      if (!mounted) return;
      final triggers = List<String>.from(state['active_triggers'] ?? []);
      _handleAlerts(triggers);
      setState(() {
        _state = state;
        _errorMessage = null;
        _previousTriggers = triggers;
        if (!_thresholdsInitialized) {
          _tempLimit =
              (state['safe_chamber_limit'] as num?)?.toDouble() ?? 60.0;
          _mq2Limit = (state['safe_mq2_limit'] as num?)?.toDouble() ?? 1.5;
          _thresholdsInitialized = true;
        }
      });
    } catch (e) {
      if (mounted && _state.isEmpty) {
        setState(() {
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
      if (hasNew) {
        _isMuted = false; // Unmute on truly new trigger
        SystemSound.play(SystemSoundType.alert);
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
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  Future<void> _saveThresholds() async {
    setState(() {
      _isSavingThresholds = true;
    });
    try {
      await ApiService.setThresholds(_tempLimit, _mq2Limit);
      if (!mounted) return;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biomass Monitor'),
        actions: [
          if (_previousTriggers.isNotEmpty)
            IconButton(
              icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
              onPressed: () => setState(() => _isMuted = !_isMuted),
            )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Live Data Section
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
                      '${_state['chamber_temp'] ?? '--'} °C',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
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
                  const Divider(),
                  ListTile(
                    leading: Icon(
                      Icons.mode_fan_off,
                      color: _state['fan_on'] == true
                          ? Colors.green
                          : Colors.grey,
                    ),
                    title: const Text('Fan Status'),
                    trailing: Text(
                      _state['fan_on'] == true ? 'ACTIVE' : 'IDLE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _state['fan_on'] == true
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(
                      Icons.water_drop,
                      color: _state['sprinkler_on'] == true
                          ? Colors.blue
                          : Colors.grey,
                    ),
                    title: const Text('Sprinkler Status'),
                    trailing: Text(
                      _state['sprinkler_on'] == true ? 'ACTIVE' : 'IDLE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _state['sprinkler_on'] == true
                            ? Colors.blue
                            : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Controls Section
          const Text(
            'Manual Controls',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.water_drop_outlined),
              title: const Text('Manual Sprinkler'),
              subtitle: const Text('Override solenoid valve'),
              value: _queuedSprinklerState ?? _state['sprinkler_on'] ?? false,
              onChanged: (val) => setState(() => _queuedSprinklerState = val),
            ),
          ),
          const SizedBox(height: 24),

          // Configuration Section
          const Text(
            'Safety Thresholds',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Safe Chamber Limit:'),
                      Text(
                        '${_tempLimit.toStringAsFixed(1)} °C',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    value: _tempLimit.clamp(20.0, 100.0),
                    min: 20.0,
                    max: 100.0,
                    divisions: 80,
                    label: '${_tempLimit.toStringAsFixed(1)} °C',
                    onChanged: (val) => setState(() => _tempLimit = val),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Safe MQ-2 Limit:'),
                      Text(
                        '${_mq2Limit.toStringAsFixed(2)} V',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    value: _mq2Limit.clamp(0.1, 3.5),
                    min: 0.1,
                    max: 3.5,
                    divisions: 34,
                    label: '${_mq2Limit.toStringAsFixed(2)} V',
                    onChanged: (val) => setState(() => _mq2Limit = val),
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
                      onPressed: _isSavingThresholds ? null : _saveThresholds,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
