import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage/app_database.dart';
import '../api_service.dart';
import '../database_helper.dart';
import '../features/alerts/alert_item.dart';
import '../features/alerts/alerts_controller.dart';
import '../features/alerts/alerts_store.dart';
import '../features/authentication/device_address_store.dart';
import '../features/monitoring/sensor_data.dart';
import '../features/monitoring/telemetry_source.dart';
import '../features/safety/safety_observation_recorder.dart';

List<SensorData> mergeSensorHistory({
  required List<SensorData> persisted,
  required List<SensorData> live,
}) {
  final readingsByTimestamp = <DateTime, SensorData>{
    for (final reading in persisted) reading.timestamp: reading,
  };
  for (final reading in live) {
    readingsByTimestamp[reading.timestamp] = reading;
  }
  final history = readingsByTimestamp.values.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return history.length > 60 ? history.sublist(history.length - 60) : history;
}

class AppStateProvider extends ChangeNotifier implements TelemetrySource {
  final SharedPreferences _prefs;
  late final DeviceAddressStore _deviceAddresses;
  final http.Client _client;
  final bool _ownsClient;
  final bool _ownsAlertsController;
  AlertsController? _alertsController;
  late final SafetyObservationRecorder _safetyObservationRecorder;

  bool _isAuthenticated = false, _isAdmin = false, _isHardwareConnected = false;
  int _currentTab = 0;
  String _currentUser = "";
  String _password = "";

  SensorData _currentData = SensorData(timestamp: DateTime.now());
  final List<SensorData> _history = [];
  int _telemetryRevision = 0;
  Timer? _pollingTimer;
  bool _isDisposed = false;
  int _sessionRevision = 0;

  AppStateProvider(
    this._prefs, {
    http.Client? client,
    AlertsController? alertsController,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _ownsAlertsController = alertsController == null {
    _alertsController =
        alertsController ?? AlertsController(AlertsStore(AppDatabase()));
    _alertsController!.addListener(_onAlertsChanged);
    _safetyObservationRecorder = SafetyObservationRecorder(_alertsController!);
    unawaited(_alertsController!.load());
    _deviceAddresses = DeviceAddressStore(_prefs);
    _deviceAddresses.migrateLegacyNodes().then((_) {
      if (!_isDisposed) notifyListeners();
    });
    _loadHistory();
  }

  bool get isAuthenticated => _isAuthenticated;
  bool get isAdmin => _isAdmin;
  @override
  bool get isHardwareConnected => _isHardwareConnected;
  bool get canResumeWithBiometrics =>
      _currentUser.isNotEmpty && _password.isNotEmpty;
  int get currentTab => _currentTab;
  String get deviceIp => _deviceAddresses.deviceIp;
  String get authorizationHeader => _basicAuthHeader;
  @override
  SensorData get currentData => _currentData;
  List<SensorData> get history => _history;
  @override
  int get telemetryRevision => _telemetryRevision;
  AlertsController get alertsController => _alertsController!;
  SafetyObservationRecorder get safetyObservationRecorder =>
      _safetyObservationRecorder;

  ApiService createSafetyApiService() => ApiService(
    baseUrl: 'http://$deviceIp/api',
    authorizationHeader: authorizationHeader,
    client: _client,
  );

  List<AlertItem> get alerts => _alertsController?.alerts ?? const [];
  int get alertCount => _alertsController?.totalAlerts ?? 0;

  Map<String, String> getSessionAnalytics() {
    if (_history.isEmpty) {
      return {
        "minT": "0.0",
        "maxT": "0.0",
        "avgT": "0.0",
        "maxMq2": "0.0",
        "avgMq2": "0.0",
        "maxAmbientTemp": "0.0",
        "avgAmbientTemp": "0.0",
        "maxMq135": "0.0",
        "avgMq135": "0.0",
        "maxPm1_0": "0.0",
        "avgPm1_0": "0.0",
        "maxPm2_5": "0.0",
        "avgPm2_5": "0.0",
        "maxPm10": "0.0",
        "avgPm10": "0.0",
      };
    }

    Map<String, String> summarise(Iterable<double?> readings, int decimals) {
      final values = readings.whereType<double>().toList();
      final minimum = values.isEmpty ? 0.0 : values.reduce(min);
      final peak = values.isEmpty ? 0.0 : values.reduce(max);
      final average = values.isEmpty
          ? 0.0
          : values.reduce((total, value) => total + value) / values.length;
      return {
        'min': minimum.toStringAsFixed(decimals),
        'max': peak.toStringAsFixed(decimals),
        'avg': average.toStringAsFixed(decimals),
      };
    }

    final chamber = summarise(
      _history.map((reading) => reading.chamberTempC),
      1,
    );
    final ambient = summarise(
      _history.map((reading) => reading.temperatureC),
      1,
    );
    final mq2 = summarise(_history.map((reading) => reading.mq2V), 2);
    final mq135 = summarise(_history.map((reading) => reading.mq135V), 2);
    final pm1_0 = summarise(_history.map((reading) => reading.pm1_0UgM3), 1);
    final pm2_5 = summarise(_history.map((reading) => reading.pm2_5UgM3), 1);
    final pm10 = summarise(_history.map((reading) => reading.pm10UgM3), 1);

    return {
      "minT": chamber['min']!,
      "maxT": chamber['max']!,
      "avgT": chamber['avg']!,
      "maxMq2": mq2['max']!,
      "avgMq2": mq2['avg']!,
      "maxAmbientTemp": ambient['max']!,
      "avgAmbientTemp": ambient['avg']!,
      "maxMq135": mq135['max']!,
      "avgMq135": mq135['avg']!,
      "maxPm1_0": pm1_0['max']!,
      "avgPm1_0": pm1_0['avg']!,
      "maxPm2_5": pm2_5['max']!,
      "avgPm2_5": pm2_5['avg']!,
      "maxPm10": pm10['max']!,
      "avgPm10": pm10['avg']!,
    };
  }

  Future<void> _loadHistory() async {
    try {
      final dbHelper = DatabaseHelper();
      final dbData = await dbHelper.getSensorData(limit: 60);
      if (_isDisposed) return;
      final mergedHistory = mergeSensorHistory(
        persisted: dbData.reversed.toList(),
        live: _history,
      );
      _history.clear();
      _history.addAll(mergedHistory);

      notifyListeners();
    } catch (error) {
      debugPrint('Local history unavailable: $error');
    }
  }

  String get _basicAuthHeader =>
      'Basic ${base64Encode(utf8.encode("$_currentUser:$_password"))}';

  Future<bool> login(String username, String password) async {
    final user = username.trim();
    if (user.isEmpty || password.isEmpty) return false;
    try {
      final authorization =
          'Basic ${base64Encode(utf8.encode("$user:$password"))}';
      final response = await _client
          .get(
            Uri.parse('http://$deviceIp/api/state'),
            headers: {'Authorization': authorization},
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return false;
    } catch (_) {
      return false;
    }
    _isAdmin = true;
    _sessionRevision++;
    _currentUser = user;
    _password = password;
    _isAuthenticated = true;
    _currentTab = 0;
    startLiveTelemetryStream();
    notifyListeners();
    return true;
  }

  Future<bool> biometricLoginSuccess() async {
    if (_currentUser.isEmpty || _password.isEmpty) return false;
    return login(_currentUser, _password);
  }

  void logout() {
    _sessionRevision++;
    _isAuthenticated = false;
    _pollingTimer?.cancel();
    notifyListeners();
  }

  void setTab(int index) {
    _currentTab = index;
    notifyListeners();
  }

  Future<void> saveDeviceIp(String ipAddress) async {
    if (ipAddress != deviceIp) _sessionRevision++;
    await _deviceAddresses.saveDeviceIp(ipAddress);
    if (!_isDisposed) notifyListeners();
  }

  Future<void> forceRefresh() async {
    await Future.delayed(const Duration(seconds: 1));
    startLiveTelemetryStream();
  }

  void startLiveTelemetryStream() {
    _pollingTimer?.cancel();
    int interval = _prefs.getInt('pollingInterval') ?? 2;

    _pollingTimer = Timer.periodic(
      Duration(seconds: interval),
      (_) => unawaited(pollOnce()),
    );
  }

  Future<void> pollOnce() async {
    if (_isDisposed) return;
    final sessionRevision = _sessionRevision;
    final observationTicket = _safetyObservationRecorder.begin();
    try {
      final response = await _client
          .get(
            Uri.parse('http://$deviceIp/api/state'),
            headers: {'Authorization': _basicAuthHeader},
          )
          .timeout(const Duration(seconds: 2));
      if (_isDisposed || sessionRevision != _sessionRevision) return;
      if (response.statusCode == 200) {
        final reportedState =
            json.decode(response.body) as Map<String, dynamic>;
        final reading = SensorData.fromJson(reportedState);
        final triggers =
            (reportedState['active_triggers'] as List<dynamic>? ?? [])
                .whereType<String>()
                .toList();
        final hadMq2Hazard = alerts.any(
          (alert) => alert.title.contains('High MQ-2 Gas Reading'),
        );
        final accepted = await _safetyObservationRecorder.accept(
          observationTicket,
          reportedState,
        );
        if (!accepted || _isDisposed || sessionRevision != _sessionRevision) {
          return;
        }
        _currentData = reading;
        _isHardwareConnected = true;
        if (triggers.contains('high_mq2_gas') &&
            reading.mq2V != null &&
            !hadMq2Hazard) {
          HapticFeedback.heavyImpact();
        }
      } else {
        if (!_safetyObservationRecorder.isCurrent(observationTicket)) return;
        _isHardwareConnected = false;
      }
    } catch (_) {
      if (_isDisposed || sessionRevision != _sessionRevision) return;
      if (!_safetyObservationRecorder.isCurrent(observationTicket)) return;
      _isHardwareConnected = false;
    }
    if (!_isHardwareConnected) {
      _currentData = SensorData(timestamp: DateTime.now());
      notifyListeners();
      return;
    }

    _history.add(_currentData);
    if (_history.length > 60) _history.removeAt(0);
    unawaited(
      DatabaseHelper().insertSensorData(_currentData).catchError((_) => 0),
    );
    _telemetryRevision++;

    notifyListeners();
  }

  void _onAlertsChanged() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _sessionRevision++;
    _pollingTimer?.cancel();
    _alertsController?.removeListener(_onAlertsChanged);
    if (_ownsAlertsController) _alertsController?.dispose();
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
