import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage/app_database.dart';
import '../database_helper.dart';
import '../features/alerts/alert_item.dart';
import '../features/alerts/alerts_controller.dart';
import '../features/alerts/alerts_store.dart';
import '../features/authentication/device_address_store.dart';
import '../features/monitoring/sensor_data.dart';
import '../features/monitoring/telemetry_source.dart';

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

  bool _isAuthenticated = false, _isAdmin = false, _isHardwareConnected = false;
  String? _loginErrorMessage;
  int _currentTab = 0;
  String _currentUser = "";
  String _password = "";

  SensorData _currentData = SensorData(timestamp: DateTime.now());
  final List<SensorData> _history = [];
  int _telemetryRevision = 0;
  Timer? _pollingTimer;

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
    unawaited(_alertsController!.load());
    _deviceAddresses = DeviceAddressStore(_prefs);
    _deviceAddresses.migrateLegacyNodes().then((_) => notifyListeners());
    _loadHistory();
  }

  bool get isAuthenticated => _isAuthenticated;
  String? get loginErrorMessage => _loginErrorMessage;
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
        "maxHumidity": "0.0",
        "avgHumidity": "0.0",
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
    final humidity = summarise(
      _history.map((reading) => reading.humidityPercent),
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
      "maxHumidity": humidity['max']!,
      "avgHumidity": humidity['avg']!,
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
    _loginErrorMessage = null;
    final stopwatch = Stopwatch()..start();
    bool fail(String message, String outcome) {
      _loginErrorMessage = message;
      debugPrint(
        'Device login: $outcome elapsed_ms=${stopwatch.elapsedMilliseconds}',
      );
      return false;
    }

    final user = username.trim();
    if (user.isEmpty || password.isEmpty) {
      return fail('Enter a username and password.', 'validation_failed');
    }
    try {
      final authorization =
          'Basic ${base64Encode(utf8.encode("$user:$password"))}';
      final response = await _client
          .get(
            Uri.parse('http://$deviceIp/api/state'),
            headers: {'Authorization': authorization},
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) {
        final message = switch (response.statusCode) {
          401 => 'Invalid username or password.',
          503 => 'Device is busy. Wait a moment and try again.',
          _ =>
            'Device returned an unexpected response (HTTP ${response.statusCode}).',
        };
        return fail(message, 'http_error status=${response.statusCode}');
      }
    } on TimeoutException {
      return fail(
        'Connection timed out after 3 seconds. Wait a moment and try again.',
        'timeout exception=TimeoutException',
      );
    } on http.ClientException catch (error) {
      return fail(
        'Cannot reach the device. Check its IP address and Wi-Fi connection.',
        'network_error exception=${error.runtimeType}',
      );
    } on FormatException {
      return fail(
        'Invalid device address. Enter its IP address, for example 192.168.1.42.',
        'invalid_address exception=FormatException',
      );
    } catch (error) {
      return fail(
        'Could not connect to the device. Please try again.',
        'unexpected_error exception=${error.runtimeType}',
      );
    }
    debugPrint(
      'Device login: success status=200 elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );
    _isAdmin = true;
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
    _isAuthenticated = false;
    _pollingTimer?.cancel();
    notifyListeners();
  }

  void setTab(int index) {
    _currentTab = index;
    notifyListeners();
  }

  Future<void> saveDeviceIp(String ipAddress) async {
    await _deviceAddresses.saveDeviceIp(ipAddress);
    notifyListeners();
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
    var triggers = <String>[];
    try {
      final response = await _client
          .get(
            Uri.parse('http://$deviceIp/api/state'),
            headers: {'Authorization': _basicAuthHeader},
          )
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final reportedState =
            json.decode(response.body) as Map<String, dynamic>;
        _currentData = SensorData.fromJson(reportedState);
        triggers = (reportedState['active_triggers'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList();
        _isHardwareConnected = true;
      } else {
        _isHardwareConnected = false;
      }
    } catch (_) {
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

    final hadGasHazard = alerts.any(
      (alert) => alert.title.contains('Gas Hazard'),
    );
    await alertsController.recordTriggers(_currentData, triggers);
    if (triggers.contains('high_mq2_gas') &&
        _currentData.mq2V != null &&
        !hadGasHazard) {
      HapticFeedback.heavyImpact();
    }
    notifyListeners();
  }

  void _onAlertsChanged() => notifyListeners();

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _alertsController?.removeListener(_onAlertsChanged);
    if (_ownsAlertsController) _alertsController?.dispose();
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
