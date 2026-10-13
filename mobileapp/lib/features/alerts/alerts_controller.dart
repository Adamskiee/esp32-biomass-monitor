import 'package:biomass_iot_app/features/alerts/alert_item.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter/foundation.dart';

class AlertsController extends ChangeNotifier {
  AlertsController(this._store);

  static const pageSize = 20;

  final AlertsStore _store;
  final List<AlertItem> _alerts = [];
  int _snapshotRowId = 0;
  int? _nextCursor;
  int _totalAlerts = 0;
  String? _severity;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isDisposed = false;
  final Set<String> _activeSensorFaults = {};
  int _nextAlertSequence = 0;

  List<AlertItem> get alerts => List.unmodifiable(_alerts);
  int get totalAlerts => _totalAlerts;
  bool get hasMoreAlerts =>
      _nextCursor != null && _alerts.length < _totalAlerts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get severity => _severity;

  Future<void> load() async {
    if (_isDisposed || _isLoading) return;
    await _performLoad(() async {
      _snapshotRowId = await _store.getLatestAlertRowId();
      _totalAlerts = await _store.getAlertCount(
        severity: _severity,
        throughRowId: _snapshotRowId,
      );
      final page = await _store.getAlertPage(
        throughRowId: _snapshotRowId,
        severity: _severity,
        limit: pageSize,
      );
      _alerts
        ..clear()
        ..addAll(page.alerts);
      _nextCursor = page.nextCursor;
    });
  }

  Future<void> setSeverity(String? severity) async {
    if (_severity == severity) return;
    _severity = severity;
    await load();
  }

  Future<void> loadMore() async {
    if (_isDisposed || _isLoading || !hasMoreAlerts) return;
    await _performLoad(() async {
      final page = await _store.getAlertPage(
        throughRowId: _snapshotRowId,
        beforeRowId: _nextCursor,
        severity: _severity,
        limit: pageSize,
      );
      _alerts.addAll(page.alerts);
      _nextCursor = page.nextCursor;
    });
  }

  Future<void> _performLoad(Future<void> Function() operation) async {
    if (_isDisposed) return;
    _isLoading = true;
    _errorMessage = null;
    _notifyListeners();
    try {
      await operation();
    } catch (_) {
      if (!_isDisposed) _errorMessage = 'Unable to load alerts. Try again.';
    } finally {
      _isLoading = false;
      _notifyListeners();
    }
  }

  Future<void> recordTriggers(SensorData reading, List<String> triggers) async {
    final sensorFaults = _sensorFaults(reading, triggers);
    for (final sensor in sensorFaults.difference(_activeSensorFaults)) {
      await _recordAlert(
        title: 'WARNING: $sensor Sensor Fault',
        description:
            '$sensor is not reporting valid data. Check the sensor connection.',
        severity: 'warning',
      );
    }
    for (final sensor in _activeSensorFaults.difference(sensorFaults)) {
      await _recordAlert(
        title: 'INFO: $sensor Sensor Recovered',
        description: '$sensor is reporting valid data again.',
        severity: 'info',
      );
    }
    _activeSensorFaults
      ..clear()
      ..addAll(sensorFaults);

    if (triggers.contains('high_mq2_gas') &&
        reading.mq2V != null &&
        !_alerts.any((alert) => alert.title.contains('Gas Hazard'))) {
      await _recordAlert(
        title: 'CRITICAL: Gas Hazard',
        description:
            'ESP32 reported a high MQ-2 reading (${reading.mq2V!.toStringAsFixed(2)} V).',
        severity: 'critical',
      );
    }
  }

  Set<String> _sensorFaults(SensorData reading, List<String> triggers) {
    final faults = <String>{};
    if (reading.reportsField('temperature_c') && reading.temperatureC == null ||
        reading.reportsField('humidity_percent') &&
            reading.humidityPercent == null) {
      faults.add('DHT22');
    }
    if (triggers.contains('temp_sensor_fault') ||
        reading.reportsField('chamber_temp_c') &&
            reading.chamberTempC == null) {
      faults.add('Thermocouple');
    }
    if (reading.reportsField('mq135_v') && reading.mq135V == null) {
      faults.add('MQ135');
    }
    if (triggers.contains('mq2_sensor_fault') ||
        reading.reportsField('mq2_v') && reading.mq2V == null) {
      faults.add('MQ2');
    }
    if (reading.reportsField('pm1_0_ug_m3') && reading.pm1_0UgM3 == null ||
        reading.reportsField('pm2_5_ug_m3') && reading.pm2_5UgM3 == null ||
        reading.reportsField('pm10_ug_m3') && reading.pm10UgM3 == null) {
      faults.add('PMS5003');
    }
    return faults;
  }

  Future<void> _recordAlert({
    required String title,
    required String description,
    required String severity,
  }) async {
    final timestamp = DateTime.now();
    final alert = AlertItem(
      id: '${timestamp.microsecondsSinceEpoch}-${_nextAlertSequence++}',
      title: title,
      description: description,
      severity: severity,
      timestamp: timestamp,
    );
    _alerts.insert(0, alert);
    _totalAlerts++;
    await _store.insertAlert(alert);
    _notifyListeners();
  }

  Future<void> removeAlert(String id) async {
    final removed = _alerts.where((alert) => alert.id == id).length;
    _alerts.removeWhere((alert) => alert.id == id);
    _totalAlerts -= removed;
    await _store.deleteAlert(id);
    _notifyListeners();
  }

  Future<void> clearAllAlerts() async {
    _alerts.clear();
    _totalAlerts = 0;
    await _store.clearAlerts();
    _notifyListeners();
  }

  void _notifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
