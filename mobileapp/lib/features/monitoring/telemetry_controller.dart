import 'dart:async';
import 'dart:math';

import 'package:biomass_iot_app/features/authentication/session_controller.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_history_store.dart';
import 'package:flutter/foundation.dart';

class TelemetryController extends ChangeNotifier {
  TelemetryController(
    this._session,
    this._historyStore, {
    required Duration pollInterval,
    required this.onReading,
  }) : _pollInterval = pollInterval;

  final SessionController _session;
  final SensorHistoryStore _historyStore;
  final Future<void> Function(SensorData reading, List<String> triggers)
  onReading;
  final List<SensorData> _history = [];
  Duration _pollInterval;
  Timer? _timer;
  bool _isPolling = false;
  bool _isHardwareConnected = false;
  SensorData _currentData = SensorData(timestamp: DateTime.now());

  bool get isHardwareConnected => _isHardwareConnected;
  SensorData get currentData => _currentData;
  List<SensorData> get history => List.unmodifiable(_history);

  Future<void> loadHistory() async {
    try {
      _history
        ..clear()
        ..addAll((await _historyStore.getSensorData(limit: 60)).reversed);
      notifyListeners();
    } catch (_) {}
  }

  void start() {
    stop();
    _timer = Timer.periodic(_pollInterval, (_) => pollOnce());
    pollOnce();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> pollOnce() async {
    if (_isPolling || !_session.isAuthenticated) return;
    _isPolling = true;
    try {
      final client = _session.createAuthenticatedClient();
      try {
        final state = await client.fetchState();
        _currentData = SensorData.fromJson(state);
        _isHardwareConnected = true;
        _history.add(_currentData);
        if (_history.length > 60) _history.removeAt(0);
        await _historyStore.insertSensorData(_currentData);
        final triggers = (state['active_triggers'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList();
        await onReading(_currentData, triggers);
      } catch (_) {
        _isHardwareConnected = false;
        _currentData = SensorData(timestamp: DateTime.now());
      } finally {
        client.close();
      }
    } finally {
      _isPolling = false;
      notifyListeners();
    }
  }

  Future<void> forceRefresh() => pollOnce();

  void updatePollInterval(Duration interval) {
    _pollInterval = interval;
    if (_timer != null) start();
  }

  Map<String, String> getSessionAnalytics() {
    final temperatures = _history
        .map((reading) => reading.chamberTempC)
        .whereType<double>()
        .toList();
    final mq2 = _history
        .map((reading) => reading.mq2V)
        .whereType<double>()
        .toList();
    double average(List<double> values) =>
        values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
    return {
      'minT': (temperatures.isEmpty ? 0 : temperatures.reduce(min))
          .toStringAsFixed(1),
      'maxT': (temperatures.isEmpty ? 0 : temperatures.reduce(max))
          .toStringAsFixed(1),
      'avgT': average(temperatures).toStringAsFixed(1),
      'maxMq2': (mq2.isEmpty ? 0 : mq2.reduce(max)).toStringAsFixed(2),
      'avgMq2': average(mq2).toStringAsFixed(2),
    };
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
