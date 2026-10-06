import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../api_service.dart';
import '../core/widgets/fluid_tile_grid.dart';
import '../core/widgets/glass_container.dart';
import '../core/widgets/glowing_card.dart';
import '../dashboard.dart';
import '../database_helper.dart';
import '../features/alerts/alert_item.dart';
import '../features/alerts/alert_timestamp.dart';
import '../features/authentication/device_address_store.dart';
import '../features/monitoring/sensor_data.dart';
import '../features/monitoring/widgets/sensor_metric_card.dart';
import '../features/safety/audit_log.dart';
import 'app_theme.dart';

export '../dashboard.dart';

part '../features/authentication/login_screen.dart';
part 'app_shell.dart';
part '../features/monitoring/home_tab.dart';
part '../features/monitoring/monitor_tab.dart';
part '../features/safety/control_tab.dart';
part '../features/alerts/alerts_tab.dart';
part '../features/settings/settings_screen.dart';
part 'app.dart';

Future<void> runLegacyApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppStateProvider(prefs)),
        ChangeNotifierProvider(create: (_) => SettingsProvider(prefs)),
      ],
      child: const MyApp(),
    ),
  );
}

// ==========================================
// 3. STATE MANAGEMENT & ANALYTICS
// ==========================================
class AppStateProvider extends ChangeNotifier {
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
  SensorData get currentData => _currentData;
  List<SensorData> get history => _history;
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

class SettingsProvider extends ChangeNotifier {
  final SharedPreferences _prefs;

  SettingsProvider(this._prefs) {
    _isDarkMode = _prefs.getBool('isDarkMode') ?? true;
    _pushNotifications = _prefs.getBool('pushNotifications') ?? true;
    _biometricLogin = _prefs.getBool('biometricLogin') ?? false;
    _pollingInterval = _prefs.getInt('pollingInterval') ?? 2;
  }

  late bool _isDarkMode, _pushNotifications, _biometricLogin;
  late int _pollingInterval;
  double _mqCalibOffset = 0.0;

  bool get isDarkMode => _isDarkMode;
  bool get pushNotifications => _pushNotifications;
  bool get biometricLogin => _biometricLogin;
  double get mqCalibOffset => _mqCalibOffset;
  int get pollingInterval => _pollingInterval;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _prefs.setBool('isDarkMode', _isDarkMode);
    notifyListeners();
  }

  void togglePush(bool val) {
    _pushNotifications = val;
    _prefs.setBool('pushNotifications', val);
    notifyListeners();
  }

  void toggleBiometric(bool val) {
    _biometricLogin = val;
    _prefs.setBool('biometricLogin', val);
    notifyListeners();
  }

  void setMqOffset(double val) {
    _mqCalibOffset = val;
    notifyListeners();
  }

  void setPollingInterval(int val) {
    _pollingInterval = val;
    _prefs.setInt('pollingInterval', val);
    notifyListeners();
  }
}

// ==========================================
// 4. RESPONSIVE FLUID LAYOUT & GLASS COMPONENTS
// ==========================================
class LegacyFluidTileGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final double spacing;

  const LegacyFluidTileGrid({
    super.key,
    required this.children,
    this.minTileWidth = 160.0,
    this.spacing = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount =
            ((constraints.maxWidth + spacing) / (minTileWidth + spacing))
                .floor();
        if (crossAxisCount < 1) crossAxisCount = 1;
        double tileWidth =
            ((constraints.maxWidth + spacing) / crossAxisCount) - spacing;
        tileWidth -= 0.01;
        if (tileWidth < 0) tileWidth = 0;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: children
              .map((child) => SizedBox(width: tileWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

class LegacyGlowingCard extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final EdgeInsetsGeometry padding;

  const LegacyGlowingCard({
    super.key,
    required this.child,
    this.glowColor = AppTheme.neonGreen,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  State<LegacyGlowingCard> createState() => _LegacyGlowingCardState();
}

class _LegacyGlowingCardState extends State<LegacyGlowingCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isHovered
                  ? widget.glowColor.withValues(alpha: 0.8)
                  : theme.dividerColor,
              width: _isHovered ? 1.5 : 1.0,
            ),
            gradient: LinearGradient(
              colors: [
                widget.glowColor.withValues(
                  alpha: _isHovered ? 0.15 : (isDark ? 0.02 : 0.05),
                ),
                Colors.transparent,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withValues(
                  alpha: _isHovered ? 0.3 : 0.05,
                ),
                blurRadius: _isHovered ? 25.0 : 10.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class LegacyGlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color? color;
  final bool hasBorder;

  const LegacyGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.color,
    this.hasBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = color ?? (isDark ? Colors.black : Colors.white);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: isDark ? 0.3 : 0.6),
            borderRadius: BorderRadius.circular(borderRadius),
            border: hasBorder
                ? Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.2),
                    width: 1.2,
                  )
                : null,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.1 : 0.4),
                Colors.white.withValues(alpha: 0.0),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 30,
                spreadRadius: -5,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ==========================================
// 5. LOGIN SCREEN
// ==========================================
