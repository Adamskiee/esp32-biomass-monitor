import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';
import '../features/alerts/alert_item.dart';
import '../features/authentication/device_address_store.dart';
import '../features/monitoring/sensor_data.dart';
import '../features/monitoring/telemetry_source.dart';
import '../features/safety/audit_log.dart';

class AppStateProvider extends ChangeNotifier implements TelemetrySource {
  final SharedPreferences _prefs;
  late final DeviceAddressStore _deviceAddresses;
  final http.Client _client;
  final bool _ownsClient;

  bool _isAuthenticated = false, _isAdmin = false, _isHardwareConnected = false;
  int _currentTab = 0;
  String _currentUser = "";
  String _password = "";

  SensorData _currentData = SensorData(timestamp: DateTime.now());
  final List<SensorData> _history = [];
  int _telemetryRevision = 0;
  final List<AlertItem> _alerts = [];
  final List<AuditLog> _auditLogs = [
    AuditLog("System Initialized", "SYSTEM", "08:00 AM"),
  ];
  Timer? _pollingTimer;

  AppStateProvider(this._prefs, {http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null {
    _deviceAddresses = DeviceAddressStore(_prefs);
    _deviceAddresses.migrateLegacyNodes().then((_) => notifyListeners());
    _loadHistory();
  }

  bool get isAuthenticated => _isAuthenticated;
  bool get isAdmin => _isAdmin;
  bool get isHardwareConnected => _isHardwareConnected;
  bool get canResumeWithBiometrics =>
      _currentUser.isNotEmpty && _password.isNotEmpty;
  int get currentTab => _currentTab;
  String get deviceIp => _deviceAddresses.deviceIp;
  String get authorizationHeader => _basicAuthHeader;
  SensorData get currentData => _currentData;
  List<SensorData> get history => _history;
  int get telemetryRevision => _telemetryRevision;
  List<AlertItem> get alerts => _alerts;
  List<AuditLog> get auditLogs => _auditLogs;

  Map<String, String> getSessionAnalytics() {
    if (_history.isEmpty) {
      return {
        "minT": "0.0",
        "maxT": "0.0",
        "avgT": "0.0",
        "maxMq2": "0.0",
        "avgMq2": "0.0",
      };
    }

    var validTemps = _history
        .where((e) => e.chamberTempC != null)
        .map((e) => e.chamberTempC!);
    double minT = validTemps.isEmpty ? 0.0 : validTemps.reduce(min);
    double maxT = validTemps.isEmpty ? 0.0 : validTemps.reduce(max);
    double avgT = validTemps.isEmpty
        ? 0.0
        : validTemps.reduce((a, b) => a + b) / validTemps.length;

    var validMq2 = _history.where((e) => e.mq2V != null).map((e) => e.mq2V!);
    double maxMq2 = validMq2.isEmpty ? 0.0 : validMq2.reduce(max);
    double avgMq2 = validMq2.isEmpty
        ? 0.0
        : validMq2.reduce((a, b) => a + b) / validMq2.length;

    return {
      "minT": minT.toStringAsFixed(1),
      "maxT": maxT.toStringAsFixed(1),
      "avgT": avgT.toStringAsFixed(1),
      "maxMq2": maxMq2.toStringAsFixed(2),
      "avgMq2": avgMq2.toStringAsFixed(2),
    };
  }

  Future<void> _loadHistory() async {
    try {
      final dbHelper = DatabaseHelper();
      final dbData = await dbHelper.getSensorData(limit: 60);
      _history.clear();
      _history.addAll(dbData.reversed);

      final dbAlerts = await dbHelper.getAlerts();
      if (dbAlerts.isNotEmpty) {
        _alerts.clear();
        _alerts.addAll(dbAlerts);
      }

      final dbLogs = await dbHelper.getAuditLogs();
      if (dbLogs.isNotEmpty) {
        _auditLogs.clear();
        _auditLogs.addAll(dbLogs);
      }

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

  void removeAlert(String id) {
    _alerts.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void clearAllAlerts() {
    _alerts.clear();
    notifyListeners();
  }

  Future<void> forceRefresh() async {
    await Future.delayed(const Duration(seconds: 1));
    startLiveTelemetryStream();
  }

  void startLiveTelemetryStream() {
    _pollingTimer?.cancel();
    int interval = _prefs.getInt('pollingInterval') ?? 2;

    _pollingTimer = Timer.periodic(Duration(seconds: interval), (_) async {
      var gasDanger = false;
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
          gasDanger = (reportedState['active_triggers'] as List<dynamic>? ?? [])
              .contains('high_mq2_gas');
          _isHardwareConnected = true;
        } else {
          _isHardwareConnected = false;
        }
      } catch (e) {
        _isHardwareConnected = false;
      }
      if (!_isHardwareConnected) {
        _currentData = SensorData(timestamp: DateTime.now());
        notifyListeners();
        return;
      }

      _history.add(_currentData);
      if (_history.length > 60) _history.removeAt(0);
      DatabaseHelper().insertSensorData(_currentData);
      _telemetryRevision++;

      if (gasDanger &&
          _currentData.mq2V != null &&
          !_alerts.any((a) => a.title.contains("Gas Hazard"))) {
        HapticFeedback.heavyImpact();
        final timestamp = DateTime.now();
        final alert = AlertItem(
          id: timestamp.millisecondsSinceEpoch.toString(),
          title: 'CRITICAL: High Gas Detected',
          description:
              'ESP32 reported a high MQ-2 reading (${_currentData.mq2V!.toStringAsFixed(2)} V).',
          severity: 'critical',
          timestamp: timestamp,
        );
        _alerts.insert(0, alert);
        DatabaseHelper().insertAlert(alert);
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
