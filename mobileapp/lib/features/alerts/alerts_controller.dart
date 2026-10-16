import 'package:biomass_iot_app/features/alerts/alert_item.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/safety/safety_condition.dart';
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
  final Set<String> _activeConditions = {};
  bool _hasLoadedAlertStates = false;
  Future<void> _triggerQueue = Future.value();
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
      await _loadAlertStates();
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
    final next = _triggerQueue.then((_) => _recordTriggers(reading, triggers));
    _triggerQueue = next.catchError((_) {});
    await next;
  }

  Future<void> _recordTriggers(
    SensorData reading,
    List<String> triggers,
  ) async {
    await _loadAlertStates();
    final sensorFaults = _sensorFaults(reading, triggers);
    if (reading.isMqWarmingUp) {
      sensorFaults.addAll(
        _activeSensorFaults.where(
          (sensor) => sensor == 'MQ135' || sensor == 'MQ2',
        ),
      );
    }
    for (final sensor in sensorFaults.difference(_activeSensorFaults)) {
      _activeSensorFaults.add(sensor);
      await _store.setAlertState('sensor:$sensor', true);
      await _recordAlert(
        title: 'WARNING: $sensor Sensor Fault',
        description:
            '$sensor is not reporting valid data. Check the sensor connection.',
        severity: 'warning',
      );
    }
    for (final sensor in _activeSensorFaults.difference(sensorFaults)) {
      _activeSensorFaults.remove(sensor);
      await _store.setAlertState('sensor:$sensor', false);
      await _recordAlert(
        title: 'INFO: $sensor Sensor Recovered',
        description: '$sensor is reporting valid data again.',
        severity: 'info',
      );
    }
    final conditions = triggers
        .map(safetyConditionFor)
        .whereType<SafetyCondition>()
        .map((condition) => condition.trigger)
        .toSet();
    for (final trigger in conditions.difference(_activeConditions)) {
      final condition = safetyConditionFor(trigger)!;
      final alert = _newAlert(
        title: '${condition.severity.toUpperCase()}: ${condition.title}',
        description: condition.describe(reading),
        severity: condition.severity,
      );
      if (await _store.recordActivation('trigger:$trigger', alert)) {
        _activeConditions.add(trigger);
        _alerts.insert(0, alert);
        _totalAlerts++;
        _notifyListeners();
      }
    }
    for (final trigger in _activeConditions.difference(conditions).toList()) {
      _activeConditions.remove(trigger);
      await _store.setAlertState('trigger:$trigger', false);
    }
  }

  Future<void> _loadAlertStates() async {
    if (_hasLoadedAlertStates) return;
    final states = await _store.getActiveAlertStates();
    _activeSensorFaults
      ..clear()
      ..addAll(
        states
            .where((state) => state.startsWith('sensor:'))
            .map((state) => state.substring('sensor:'.length)),
      );
    _activeConditions
      ..clear()
      ..addAll(
        states
            .where((state) => state.startsWith('trigger:'))
            .map((state) => state.substring('trigger:'.length)),
      );
    if (states.contains('gas_hazard')) {
      _activeConditions.add('high_mq2_gas');
      await _store.setAlertState('gas_hazard', false);
      await _store.setAlertState('trigger:high_mq2_gas', true);
    }
    _hasLoadedAlertStates = true;
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
    if (!reading.isMqWarmingUp &&
        reading.reportsField('mq135_v') &&
        reading.mq135V == null) {
      faults.add('MQ135');
    }
    if (!reading.isMqWarmingUp &&
        (triggers.contains('mq2_sensor_fault') ||
            reading.reportsField('mq2_v') && reading.mq2V == null)) {
      faults.add('MQ2');
    }
    if ((reading.reportsField('pm1_0_ug_m3') ||
                reading.reportsField('pm1_ug_m3')) &&
            reading.pm1_0UgM3 == null ||
        (reading.reportsField('pm2_5_ug_m3') ||
                reading.reportsField('pm25_ug_m3')) &&
            reading.pm2_5UgM3 == null ||
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
    final alert = _newAlert(
      title: title,
      description: description,
      severity: severity,
    );
    _alerts.insert(0, alert);
    _totalAlerts++;
    await _store.insertAlert(alert);
    _notifyListeners();
  }

  AlertItem _newAlert({
    required String title,
    required String description,
    required String severity,
  }) {
    final timestamp = DateTime.now();
    return AlertItem(
      id: '${timestamp.microsecondsSinceEpoch}-${_nextAlertSequence++}',
      title: title,
      description: description,
      severity: severity,
      timestamp: timestamp,
    );
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
    _activeSensorFaults.clear();
    _activeConditions.clear();
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
