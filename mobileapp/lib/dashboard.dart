import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';

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

  double _tempLimit = 60.0;
  double _mq2Limit = 1.5;
  bool _thresholdsDirty = false;
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
          _tempLimit =
              (state['threshold_chamber_temp_c'] as num?)?.toDouble() ?? 60.0;
          _mq2Limit = (state['threshold_mq2_v'] as num?)?.toDouble() ?? 1.5;
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
      await widget.apiService.setThresholds(_tempLimit, _mq2Limit);
      if (!mounted) return;
      setState(() => _thresholdsDirty = false);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biomass Monitor'),
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
              value: _state['sprinkler_on'] == true,
              onChanged: _isOffline || _queuedSprinklerState != null
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
                    value: _tempLimit.clamp(20.0, 150.0),
                    min: 20.0,
                    max: 150.0,
                    divisions: 130,
                    label: '${_tempLimit.toStringAsFixed(1)} °C',
                    onChanged: _isOffline || _isSavingThresholds
                        ? null
                        : (val) => setState(() {
                            _tempLimit = val;
                            _thresholdsDirty = true;
                          }),
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
                    value: _mq2Limit.clamp(0.1, 5.0),
                    min: 0.1,
                    max: 5.0,
                    divisions: 49,
                    label: '${_mq2Limit.toStringAsFixed(2)} V',
                    onChanged: _isOffline || _isSavingThresholds
                        ? null
                        : (val) => setState(() {
                            _mq2Limit = val;
                            _thresholdsDirty = true;
                          }),
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
                      onPressed:
                          _isOffline || _isSavingThresholds || !_thresholdsDirty
                          ? null
                          : _saveThresholds,
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
