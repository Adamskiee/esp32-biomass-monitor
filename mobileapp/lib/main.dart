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
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'database_helper.dart';
import 'dashboard.dart';
export 'dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase initialization info: $e");
  }
  
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
// 1. DYNAMIC THEME ENGINE & UI CONSTANTS
// ==========================================
class AppTheme {
  static const Color backgroundDark = Color(0xFF090A0F); // Deeper, richer background
  static const Color cardDark = Color(0xFF12141D);       // Sleeker card color
  static const Color cardBorder = Color(0xFF1F2433);     // Subtle border

  static const Color neonGreen = Color(0xFF30D158);
  static const Color neonBlue = Color(0xFF0A84FF);
  static const Color neonOrange = Color(0xFFFF9F0A);
  static const Color neonRed = Color(0xFFFF453A);
  static const Color neonPurple = Color(0xFFBF5AF2);

  static ThemeData getDarkTheme() {
    return ThemeData(
      useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundDark,
      cardColor: cardDark,
      dividerColor: cardBorder,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      colorScheme: const ColorScheme.dark(primary: neonGreen, surface: backgroundDark),
    );
  }

  static ThemeData getLightTheme() {
    return ThemeData(
      useMaterial3: true, brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Cleaner light mode bg
      cardColor: const Color(0xFFFFFFFF),
      dividerColor: const Color(0xFFE2E8F0),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      colorScheme: const ColorScheme.light(primary: neonGreen, surface: Color(0xFFF8FAFC)),
    );
  }
}

// ==========================================
// 2. DATA MODELS
// ==========================================
class SensorData {
  final double? temperatureC, chamberTempC, mq135V, mq2V;
  final DateTime timestamp;
  
  SensorData({this.temperatureC, this.chamberTempC, this.mq135V, this.mq2V, required this.timestamp});

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      temperatureC: json['temperature_c'] != null ? (json['temperature_c'] as num).toDouble() : null,
      chamberTempC: json['chamber_temp_c'] != null ? (json['chamber_temp_c'] as num).toDouble() : null,
      mq135V: json['mq135_v'] != null ? (json['mq135_v'] as num).toDouble() : null,
      mq2V: json['mq2_v'] != null ? (json['mq2_v'] as num).toDouble() : null,
      timestamp: DateTime.now(),
    );
  }
}

class AlertItem {
  final String id, title, description, severity, time;
  AlertItem({required this.id, required this.title, required this.description, required this.severity, required this.time});
}

class AuditLog {
  final String action, user, timestamp;
  AuditLog(this.action, this.user, this.timestamp);
}

class IoTNode {
  String id, name, ipAddress, macAddress;
  IoTNode(this.id, this.name, this.ipAddress, this.macAddress);
  
  factory IoTNode.fromJson(Map<String, dynamic> json) => IoTNode(json['id'], json['name'], json['ipAddress'], json['macAddress']);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'ipAddress': ipAddress, 'macAddress': macAddress};
}

// ==========================================
// 3. STATE MANAGEMENT & ANALYTICS
// ==========================================
class AppStateProvider extends ChangeNotifier {
  final SharedPreferences _prefs;
  
  bool _isAuthenticated = false, _isAdmin = false, _isHardwareConnected = false;
  final int _batteryLevel = 92;
  int _rssi = -42, _currentTab = 0;
  String _currentUser = "";
  String _password = "";
  
  List<IoTNode> _availableNodes = [];
  late IoTNode _activeNode;
  
  SensorData _currentData = SensorData(temperatureC: 28.5, chamberTempC: 30.0, mq135V: 1.2, mq2V: 1.5, timestamp: DateTime.now());
  final List<SensorData> _history = [];
  final List<AlertItem> _alerts = [];
  final List<AuditLog> _auditLogs = [AuditLog("System Initialized", "SYSTEM", "08:00 AM")];
  Timer? _pollingTimer;

  AppStateProvider(this._prefs) { 
    _loadNodes();
    _activeNode = _availableNodes[0]; 
    _loadHistory(); 
  }

  void _loadNodes() {
    final nodesStr = _prefs.getString('savedNodes');
    if (nodesStr != null) {
      final List dec = json.decode(nodesStr);
      _availableNodes = dec.map((n) => IoTNode.fromJson(n)).toList();
    } else {
      _availableNodes = [
        IoTNode("1", "JPLPC Malvar Node 1", "192.168.4.1", "24:0A:C4:00:01:10"),
        IoTNode("2", "JPLPC Malvar Node 2", "192.168.1.51", "24:0A:C4:00:01:11"),
      ];
      _saveNodes();
    }
  }

  void _saveNodes() {
    _prefs.setString('savedNodes', json.encode(_availableNodes.map((n) => n.toJson()).toList()));
  }

  void updateNode(IoTNode node, String name, String ip, String mac) {
    node.name = name;
    node.ipAddress = ip;
    node.macAddress = mac;
    _saveNodes();
    notifyListeners();
    if (_activeNode.id == node.id) {
      startLiveTelemetryStream();
    }
  }

  bool get isAuthenticated => _isAuthenticated;
  bool get isAdmin => _isAdmin;
  bool get isHardwareConnected => _isHardwareConnected;
  int get currentTab => _currentTab;
  IoTNode get activeNode => _activeNode;
  List<IoTNode> get availableNodes => _availableNodes;
  int get batteryLevel => _batteryLevel;
  int get rssi => _rssi;
  SensorData get currentData => _currentData;
  List<SensorData> get history => _history;
  List<AlertItem> get alerts => _alerts;
  List<AuditLog> get auditLogs => _auditLogs;

  Map<String, String> getSessionAnalytics() {
    if (_history.isEmpty) return {"minT": "0.0", "maxT": "0.0", "avgT": "0.0", "maxCO": "0.0", "avgCO": "0.0"};
    
    var validTemps = _history.where((e) => e.chamberTempC != null).map((e) => e.chamberTempC!);
    double minT = validTemps.isEmpty ? 0.0 : validTemps.reduce(min);
    double maxT = validTemps.isEmpty ? 0.0 : validTemps.reduce(max);
    double avgT = validTemps.isEmpty ? 0.0 : validTemps.reduce((a, b) => a + b) / validTemps.length;
    
    var validMq2 = _history.where((e) => e.mq2V != null).map((e) => e.mq2V!);
    double maxCO = validMq2.isEmpty ? 0.0 : validMq2.reduce(max);
    double avgCO = validMq2.isEmpty ? 0.0 : validMq2.reduce((a, b) => a + b) / validMq2.length;

    return {
      "minT": minT.toStringAsFixed(1),
      "maxT": maxT.toStringAsFixed(1),
      "avgT": avgT.toStringAsFixed(1),
      "maxCO": maxCO.toStringAsFixed(2),
      "avgCO": avgCO.toStringAsFixed(2),
    };
  }

  Future<void> _loadHistory() async {
    final dbHelper = DatabaseHelper();
    
    // Load Sensor Data
    List<SensorData> dbData = await dbHelper.getSensorData(limit: 60);
    _history.clear();
    _history.addAll(dbData.reversed);
    
    // Load Alerts
    List<AlertItem> dbAlerts = await dbHelper.getAlerts();
    if (dbAlerts.isNotEmpty) {
      _alerts.clear();
      _alerts.addAll(dbAlerts);
    }
    
    // Load Audit Logs
    List<AuditLog> dbLogs = await dbHelper.getAuditLogs();
    if (dbLogs.isNotEmpty) {
      _auditLogs.clear();
      _auditLogs.addAll(dbLogs);
    }
    
    notifyListeners();
  }

  String get _basicAuthHeader => 'Basic ${base64Encode(utf8.encode("$_currentUser:$_password"))}';

  void login(String username, String password) {
    if ((username.trim() == 'admin' && password == 'admin') || (username.trim() == 'user' && password == 'user')) {
      _isAdmin = (username.trim() == 'admin'); 
      _currentUser = username.trim().toLowerCase(); // ESP32 expects lower case for basic auth
      _password = password;
      _isAuthenticated = true; 
      _currentTab = 0;
      startLiveTelemetryStream(); 
      notifyListeners();
    }
  }

  void biometricLoginSuccess(bool isAdminUser) {
    _isAdmin = isAdminUser;
    _currentUser = isAdminUser ? "admin" : "user";
    _password = isAdminUser ? "admin" : "user"; // hardcoded for fallback
    _isAuthenticated = true;
    _currentTab = 0;
    startLiveTelemetryStream();
    notifyListeners();
  }

  void logout() { 
    _isAuthenticated = false; 
    _pollingTimer?.cancel(); 
    notifyListeners(); 
  }

  void setTab(int index) { _currentTab = index; notifyListeners(); }

  void setActiveNode(IoTNode node) {
    _activeNode = node; 
    _isHardwareConnected = false; 
    _history.clear(); 
    _loadHistory(); 
    _addAuditLog("Switched Node View");
    notifyListeners();
  }

  Future<void> _addAuditLog(String actionName) async {
    final log = AuditLog(actionName, _currentUser, "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}");
    _auditLogs.insert(0, log);
    await DatabaseHelper().insertAuditLog(log);
    notifyListeners();
  }

  void removeAlert(String id) { _alerts.removeWhere((a) => a.id == id); notifyListeners(); }
  void clearAllAlerts() { _alerts.clear(); notifyListeners(); }
  Future<void> forceRefresh() async { await Future.delayed(const Duration(seconds: 1)); startLiveTelemetryStream(); }

  void startLiveTelemetryStream() {
    _pollingTimer?.cancel();
    int interval = _prefs.getInt('pollingInterval') ?? 2;

    _pollingTimer = Timer.periodic(Duration(seconds: interval), (_) async {
      try {
        final response = await http.get(
          Uri.parse('http://${_activeNode.ipAddress}/api/state'),
          headers: { 'Authorization': _basicAuthHeader },
        ).timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          _currentData = SensorData.fromJson(json.decode(response.body));
          _isHardwareConnected = true;
          _rssi = -40 - Random().nextInt(15);
        } else { _isHardwareConnected = false; }
      } catch (e) {
        _isHardwareConnected = false;
        // Fallback UI Simulation
        final r = Random();
        _currentData = SensorData(
          temperatureC: ((_currentData.temperatureC ?? 25.0) + (r.nextDouble() * 0.8 - 0.4)).clamp(20.0, 55.0),
          chamberTempC: ((_currentData.chamberTempC ?? 120.0) + (r.nextDouble() * 2.0 - 1.0)).clamp(20.0, 150.0),
          mq135V: ((_currentData.mq135V ?? 2.1) + r.nextDouble() * 0.1 - 0.05).clamp(0.1, 5.0),
          mq2V: ((_currentData.mq2V ?? 1.5) + r.nextDouble() * 0.2 - 0.1).clamp(0.1, 5.0),
          timestamp: DateTime.now(),
        );
        _rssi = -60 - Random().nextInt(10);
      }
      
      _history.add(_currentData);
      if (_history.length > 60) _history.removeAt(0);
      DatabaseHelper().insertSensorData(_currentData);

      if (_currentData.mq2V != null && _currentData.mq2V! > 2.5 && !_alerts.any((a) => a.title.contains("Gas Hazard"))) {
        HapticFeedback.heavyImpact();
        final alert = AlertItem(id: DateTime.now().millisecondsSinceEpoch.toString(), title: 'CRITICAL: High Gas Detected', description: 'MQ-2 voltage crossed safe limits (${_currentData.mq2V!.toStringAsFixed(2)} V).', severity: 'critical', time: 'Just now');
        _alerts.insert(0, alert);
        DatabaseHelper().insertAlert(alert);
      }
      notifyListeners();
    });
  }

  Future<bool> sendHardwareCommand(String endpoint, bool state) async {
    String actionName = "${state ? 'Activated' : 'Deactivated'} $endpoint";
    _addAuditLog(actionName);

    try {
      final res = await http.post(
        Uri.parse('http://${_activeNode.ipAddress}/api/control/$endpoint'),
        headers: { 'Content-Type': 'application/json', 'Authorization': _basicAuthHeader },
        body: json.encode({'state': state})
      ).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (e) { return false; }
  }

  // --- ESP32 API: Settings ---
  Future<Map<String, dynamic>?> fetchEsp32Settings() async {
    try {
      final response = await http.get(
        Uri.parse('http://${_activeNode.ipAddress}/api/settings'),
        headers: { 'Authorization': _basicAuthHeader },
      ).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) { /* Ignore */ }
    return null;
  }

  Future<bool> updateEsp32Settings(double chamberTempC, double mq2V) async {
    try {
      final payload = json.encode({
        "threshold_chamber_temp_c": chamberTempC,
        "threshold_mq2_v": mq2V
      });
      if (payload.length > 256) return false; // ESP32 limitation
      
      final res = await http.post(
        Uri.parse('http://${_activeNode.ipAddress}/api/settings'),
        headers: { 'Content-Type': 'application/json', 'Authorization': _basicAuthHeader },
        body: payload,
      ).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (e) { return false; }
  }

  @override
  void dispose() { _pollingTimer?.cancel(); super.dispose(); }
}

class SettingsProvider extends ChangeNotifier {
  final SharedPreferences _prefs;

  SettingsProvider(this._prefs) {
    _isDarkMode = _prefs.getBool('isDarkMode') ?? true;
    _pushNotifications = _prefs.getBool('pushNotifications') ?? true;
    _biometricLogin = _prefs.getBool('biometricLogin') ?? false;
    _tempThreshold = _prefs.getDouble('tempThreshold') ?? 45.0;
    _coThreshold = _prefs.getDouble('coThreshold') ?? 1.5;
    _pollingInterval = _prefs.getInt('pollingInterval') ?? 2;
  }

  late bool _isDarkMode, _pushNotifications, _biometricLogin;
  late double _tempThreshold, _coThreshold;
  late int _pollingInterval;
  double _mqCalibOffset = 0.0;

  bool get isDarkMode => _isDarkMode;
  bool get pushNotifications => _pushNotifications;
  bool get biometricLogin => _biometricLogin;
  double get tempThreshold => _tempThreshold;
  double get coThreshold => _coThreshold;
  double get mqCalibOffset => _mqCalibOffset;
  int get pollingInterval => _pollingInterval;

  void toggleTheme() { _isDarkMode = !_isDarkMode; _prefs.setBool('isDarkMode', _isDarkMode); notifyListeners(); }
  void togglePush(bool val) { _pushNotifications = val; _prefs.setBool('pushNotifications', val); notifyListeners(); }
  void toggleBiometric(bool val) { _biometricLogin = val; _prefs.setBool('biometricLogin', val); notifyListeners(); }
  void setTempThreshold(double val) { _tempThreshold = val; _prefs.setDouble('tempThreshold', val); notifyListeners(); }
  void setCoThreshold(double val) { _coThreshold = val; _prefs.setDouble('coThreshold', val); notifyListeners(); }
  void setMqOffset(double val) { _mqCalibOffset = val; notifyListeners(); }
  
  void setPollingInterval(int val) { 
    _pollingInterval = val; 
    _prefs.setInt('pollingInterval', val); 
    notifyListeners(); 
  }
}

// ==========================================
// 4. RESPONSIVE FLUID LAYOUT & GLASS COMPONENTS
// ==========================================
class FluidTileGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final double spacing;

  const FluidTileGrid({super.key, required this.children, this.minTileWidth = 160.0, this.spacing = 16.0});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = ((constraints.maxWidth + spacing) / (minTileWidth + spacing)).floor();
        if (crossAxisCount < 1) crossAxisCount = 1;
        double tileWidth = ((constraints.maxWidth + spacing) / crossAxisCount) - spacing;
        tileWidth -= 0.01; 
        if (tileWidth < 0) tileWidth = 0;

        return Wrap(
          spacing: spacing, runSpacing: spacing,
          children: children.map((child) => SizedBox(width: tileWidth, child: child)).toList(),
        );
      },
    );
  }
}

class GlowingCard extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final EdgeInsetsGeometry padding;

  const GlowingCard({super.key, required this.child, this.glowColor = AppTheme.neonGreen, this.padding = const EdgeInsets.all(24)});

  @override
  State<GlowingCard> createState() => _GlowingCardState();
}

class _GlowingCardState extends State<GlowingCard> {
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
            border: Border.all(color: _isHovered ? widget.glowColor.withValues(alpha: 0.8) : theme.dividerColor, width: _isHovered ? 1.5 : 1.0),
            gradient: LinearGradient(colors: [widget.glowColor.withValues(alpha: _isHovered ? 0.15 : (isDark ? 0.02 : 0.05)), Colors.transparent], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: widget.glowColor.withValues(alpha: _isHovered ? 0.3 : 0.05), blurRadius: _isHovered ? 25.0 : 10.0, offset: const Offset(0, 4))],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color? color;
  final bool hasBorder;

  const GlassContainer({super.key, required this.child, this.borderRadius = 20, this.color, this.hasBorder = true});

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
            border: hasBorder ? Border.all(color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.2), width: 1.2) : null,
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.1 : 0.4),
                Colors.white.withValues(alpha: 0.0),
              ]
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 30, spreadRadius: -5)
            ]
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
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController(text: 'admin');
  final LocalAuthentication auth = LocalAuthentication();
  bool _isLoading = false;
  String _errorMsg = '';
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat(reverse: true);
    _checkBiometrics();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    final settings = context.read<SettingsProvider>();
    if (settings.biometricLogin) {
      try {
        final bool didAuthenticate = await auth.authenticate(localizedReason: 'Authenticate to access Biomass Terminal');
        if (didAuthenticate && mounted) context.read<AppStateProvider>().biometricLoginSuccess(true);
      } catch (e) { /* Fallback to manual login */ }
    }
  }

  void _handleLogin() {
    setState(() { _isLoading = true; _errorMsg = ''; });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final u = _userCtrl.text.trim();
      final p = _passCtrl.text;
      if ((u == 'admin' && p == 'admin') || (u == 'user' && p == 'user')) {
        context.read<AppStateProvider>().login(u, p);
      } else {
        setState(() { _isLoading = false; _errorMsg = 'Invalid credentials.'; });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      body: Stack(
        children: [
          // Animated Background
          AnimatedBuilder(
            animation: _animCtrl,
            builder: (context, child) {
              return Stack(
                children: [
                  Positioned(
                    top: -150 + (_animCtrl.value * 50),
                    left: -150 + (_animCtrl.value * 30),
                    child: Container(width: 600, height: 600, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [AppTheme.neonGreen.withValues(alpha: 0.15), Colors.transparent]))),
                  ),
                  Positioned(
                    bottom: -200 + ((1 - _animCtrl.value) * 80),
                    right: -100 - (_animCtrl.value * 40),
                    child: Container(width: 700, height: 700, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [AppTheme.neonBlue.withValues(alpha: 0.1), Colors.transparent]))),
                  ),
                  Positioned(
                    top: 100 + (_animCtrl.value * 100),
                    right: -150,
                    child: Container(width: 400, height: 400, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [AppTheme.neonOrange.withValues(alpha: 0.08), Colors.transparent]))),
                  ),
                ],
              );
            },
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: GlassContainer(
                borderRadius: 32,
                color: theme.cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: SizedBox(
                    width: 360,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<double>(
                          duration: const Duration(seconds: 1),
                          tween: Tween(begin: 0.0, end: 1.0),
                          curve: Curves.easeOutExpo,
                          builder: (context, val, child) => Transform.scale(
                            scale: val,
                            child: child,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: theme.cardColor.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.neonGreen.withValues(alpha: 0.3), width: 1.5),
                              boxShadow: [BoxShadow(color: AppTheme.neonGreen.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 5)],
                            ),
                            child: const Icon(CupertinoIcons.flame_fill, size: 64, color: AppTheme.neonGreen),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text("Biomass Core", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                        const SizedBox(height: 8),
                        const Text("Telemetry & Command Protocol", style: TextStyle(color: Colors.grey, fontSize: 14, letterSpacing: 0.5)),
                        const SizedBox(height: 48),
                        TextField(controller: _userCtrl, style: TextStyle(color: theme.textTheme.bodyLarge?.color), decoration: _inputDec("Operator ID", CupertinoIcons.person_solid, theme)),
                        const SizedBox(height: 20),
                        TextField(controller: _passCtrl, obscureText: true, style: TextStyle(color: theme.textTheme.bodyLarge?.color), decoration: _inputDec("Passcode", CupertinoIcons.lock_fill, theme), onSubmitted: (_) => _handleLogin()),
                        if (_errorMsg.isNotEmpty) ...[const SizedBox(height: 16), Text(_errorMsg, style: const TextStyle(color: AppTheme.neonRed, fontSize: 13, fontWeight: FontWeight.bold))],
                        const SizedBox(height: 40),
                        SizedBox(
                          width: double.infinity, height: 60,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.neonGreen,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _isLoading ? null : _handleLogin,
                            child: _isLoading ? const CircularProgressIndicator(color: Colors.black) : const Text("INITIATE CONNECTION", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                          ),
                        ),
                        if (settings.biometricLogin) ...[
                          const SizedBox(height: 24),
                          TextButton.icon(
                            icon: const Icon(CupertinoIcons.lock_shield_fill, color: AppTheme.neonBlue),
                            label: const Text("Biometric Override", style: TextStyle(color: AppTheme.neonBlue, fontWeight: FontWeight.bold)),
                            onPressed: _checkBiometrics,
                          )
                        ]
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon, ThemeData theme) {
    return InputDecoration(
      labelText: label, prefixIcon: Icon(icon, color: Colors.grey, size: 20), filled: true, fillColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.5),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.dividerColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.neonGreen, width: 1.5)),
    );
  }
}

// ==========================================
// 6. MAIN APP SHELL (RESPONSIVE NAVIGATION)
// ==========================================
class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});
  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  final List<Widget> _screens = const [HomeTab(), MonitorTab(), ControlTab(), AlertsTab(), SettingsScreen()];

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Disconnect Terminal?"),
        content: const Text("You will stop receiving live push notifications and telemetry updates."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonRed, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppStateProvider>().logout();
            },
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 850;

    Widget offlineBanner = !state.isHardwareConnected 
      ? GestureDetector(
          onTap: () => state.startLiveTelemetryStream(),
          child: Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16), color: AppTheme.neonRed,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(CupertinoIcons.wifi_slash, color: Colors.white, size: 18), const SizedBox(width: 12), Expanded(child: Text("Hardware Offline: Tap to reconnect to ${state.activeNode.ipAddress}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))]),
          ),
        ) : const SizedBox.shrink();

    Widget nodeSelector = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: theme.dividerColor)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<IoTNode>(
          isExpanded: true,
          value: state.activeNode,
          dropdownColor: theme.cardColor,
          icon: const Icon(CupertinoIcons.chevron_down, size: 16, color: Colors.grey),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color),
          items: state.availableNodes.map((node) => DropdownMenuItem(value: node, child: Text(node.name))).toList(),
          onChanged: (node) { if (node != null) state.setActiveNode(node); },
        ),
      ),
    );

    return Scaffold(
      extendBody: true, 
      appBar: !isDesktop ? AppBar(
        backgroundColor: theme.cardColor.withValues(alpha: 0.9), elevation: 0,
        title: Text("IoT Biomass Terminal", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          Icon(CupertinoIcons.wifi, color: state.isHardwareConnected ? AppTheme.neonGreen : AppTheme.neonRed, size: 20),
          const SizedBox(width: 16),
          IconButton(icon: const Icon(CupertinoIcons.power, color: AppTheme.neonRed, size: 20), onPressed: () => _showLogoutConfirmation(context)),
          const SizedBox(width: 8),
        ],
      ) : null,
      body: Row(
        children: [
          if (isDesktop)
            Container(
              width: 260, decoration: BoxDecoration(color: theme.cardColor, border: Border(right: BorderSide(color: theme.dividerColor))),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                    child: Row(children: [const Icon(CupertinoIcons.flame_fill, color: AppTheme.neonGreen, size: 32), const SizedBox(width: 12), Expanded(child: Text("BIOMASS IOT", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)))]),
                  ),
                  nodeSelector,
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _sidebarItem(0, CupertinoIcons.house_fill, "Home Dashboard", theme),
                        _sidebarItem(1, CupertinoIcons.wind, "Air Quality Monitor", theme),
                        _sidebarItem(2, Icons.tune, "System Control", theme),
                        _sidebarItem(3, CupertinoIcons.bell_fill, "Active Alerts", theme, badge: state.alerts.length),
                        _sidebarItem(4, CupertinoIcons.gear_solid, "Settings & Admin", theme),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonRed.withValues(alpha: 0.1), foregroundColor: AppTheme.neonRed, elevation: 0, minimumSize: const Size(double.infinity, 50)),
                      icon: const Icon(CupertinoIcons.power),
                      label: const Text("Logout"),
                      onPressed: () => _showLogoutConfirmation(context),
                    ),
                  )
                ],
              ),
            ),
          Expanded(
            child: Column(
              children: [
                offlineBanner,
                if (!isDesktop) nodeSelector,
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300), 
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.95, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey<int>(state.currentTab), child: _screens[state.currentTab])
                  )
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: !isDesktop ? Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
        child: GlassContainer(
          borderRadius: 30,
          color: theme.cardColor.withValues(alpha: 0.85),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: BottomNavigationBar(
              currentIndex: state.currentTab, type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent, elevation: 0,
              selectedItemColor: AppTheme.neonGreen, unselectedItemColor: Colors.grey,
              showSelectedLabels: false, showUnselectedLabels: false,
              onTap: (index) => state.setTab(index),
              items: const [
                BottomNavigationBarItem(icon: Icon(CupertinoIcons.house_fill, size: 26), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(CupertinoIcons.wind, size: 26), label: 'Monitor'),
                BottomNavigationBarItem(icon: Icon(Icons.tune, size: 26), label: 'Control'),
                BottomNavigationBarItem(icon: Icon(CupertinoIcons.bell_fill, size: 26), label: 'Alerts'),
                BottomNavigationBarItem(icon: Icon(CupertinoIcons.bars, size: 26), label: 'More'),
              ],
            ),
          ),
        ),
      ) : null,
    );
  }

  Widget _sidebarItem(int index, IconData icon, String title, ThemeData theme, {int badge = 0}) {
    final state = context.watch<AppStateProvider>();
    bool isSel = state.currentTab == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => state.setTab(index),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: isSel ? AppTheme.neonGreen.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(icon, color: isSel ? AppTheme.neonGreen : Colors.grey, size: 20),
              const SizedBox(width: 16),
              Expanded(child: Text(title, style: TextStyle(color: isSel ? theme.textTheme.bodyLarge?.color : Colors.grey, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, fontSize: 14))),
              if (badge > 0)
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.neonOrange, borderRadius: BorderRadius.circular(10)), child: Text(badge.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// TAB 1: HOME (DASHBOARD)
// ==========================================
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  int _chartTimeframe = 0; 
  List<SensorData>? _historicalData;
  bool _isLoadingHistory = false;

  Future<void> _fetchHistoricalData(int index) async {
    setState(() {
      _chartTimeframe = index;
      if (index == 0) {
        _historicalData = null;
        _isLoadingHistory = false;
      } else {
        _isLoadingHistory = true;
      }
    });

    if (index > 0) {
      int hours = index == 1 ? 1 : 24;
      final data = await DatabaseHelper().getAggregatedSensorData(hours);
      if (mounted) {
        setState(() {
          _historicalData = data;
          _isLoadingHistory = false;
        });
      }
    }
  }

  void _showDiagnosticDialog(BuildContext context, String moduleName, bool isHealthy) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(isHealthy ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.exclamationmark_triangle_fill, color: isHealthy ? AppTheme.neonGreen : AppTheme.neonOrange),
            const SizedBox(width: 12),
            Expanded(child: Text("$moduleName Diagnostics", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Text(isHealthy ? "This module is operating within standard parameters. No maintenance required." : "Warning: This module is detecting irregularities or requires maintenance inspection.", style: const TextStyle(color: Colors.grey)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close", style: TextStyle(color: AppTheme.neonBlue)))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final data = state.currentData;
    final theme = Theme.of(context);
    final isCompact = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: RefreshIndicator(
            color: AppTheme.neonGreen, backgroundColor: theme.cardColor,
            onRefresh: () => state.forceRefresh(),
            child: ListView(
              padding: EdgeInsets.only(left: isCompact ? 16 : 24, right: isCompact ? 16 : 24, top: isCompact ? 16 : 24, bottom: 160), 
              children: [
                FluidTileGrid(
                  minTileWidth: isCompact ? 150 : 260,
                  spacing: isCompact ? 12 : 16,
                  children: [
                    _metricCard("Ambient Temp", data.temperatureC ?? 0.0, " °C", CupertinoIcons.thermometer, AppTheme.neonOrange, theme, decimals: 1, isCompact: isCompact, maxVal: 50.0),
                    _metricCard("Chamber Temp", data.chamberTempC ?? 0.0, " °C", CupertinoIcons.flame_fill, data.chamberTempC != null && data.chamberTempC! > 100 ? AppTheme.neonRed : AppTheme.neonOrange, theme, isCompact: isCompact, maxVal: 150.0),
                    _metricCard("MQ135 Gas", data.mq135V ?? 0.0, " V", CupertinoIcons.cloud_fill, AppTheme.neonBlue, theme, decimals: 2, isCompact: isCompact, maxVal: 5.0),
                    _metricCard("MQ2 Smoke", data.mq2V ?? 0.0, " V", CupertinoIcons.smoke_fill, AppTheme.neonPurple, theme, decimals: 2, isCompact: isCompact, maxVal: 5.0),
                  ],
                ),
                const SizedBox(height: 32),

                Text("System Status", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12, runSpacing: 12,
                  children: [
                    _statusChip(context, "Combustion Chamber", true),
                    _statusChip(context, "DC Blower Fan", true),
                    _statusChip(context, "Filtration Module", true),
                    _statusChip(context, "Sprinkler System", false, warning: true),
                  ],
                ),
                const SizedBox(height: 32),

                GlowingCard(
                  glowColor: AppTheme.neonBlue, padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 16,
                        children: [
                          Text("Real-Time Telemetry Trends", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 16)),
                          CupertinoSegmentedControl<int>(
                            selectedColor: AppTheme.neonBlue, borderColor: AppTheme.neonBlue, unselectedColor: theme.cardColor, groupValue: _chartTimeframe,
                            children: const {0: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("Live", style: TextStyle(fontSize: 11))), 1: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("1H", style: TextStyle(fontSize: 11))), 2: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("24H", style: TextStyle(fontSize: 11)))},
                            onValueChanged: _fetchHistoricalData,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(_chartTimeframe == 0 ? "Temperature & CO over the last 60 seconds. Tap chart for details." : "Historical average trends.", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (_isLoadingHistory) {
                            return SizedBox(height: constraints.maxWidth < 600 ? 200 : 350, child: const Center(child: CircularProgressIndicator()));
                          }
                          final chartData = _chartTimeframe == 0 ? state.history : (_historicalData ?? []);
                          if (chartData.isEmpty) {
                            return SizedBox(height: constraints.maxWidth < 600 ? 200 : 350, child: const Center(child: Text("No historical data available", style: TextStyle(color: Colors.grey))));
                          }
                          return SizedBox(height: constraints.maxWidth < 600 ? 200 : 350, child: LineChart(_buildChartData(chartData, theme)));
                        }
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Recent Alerts", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
                    TextButton(onPressed: () => context.read<AppStateProvider>().setTab(3), child: const Text("See all", style: TextStyle(color: AppTheme.neonGreen))),
                  ],
                ),
                if (state.alerts.isNotEmpty)
                  ...state.alerts.take(2).map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: theme.cardColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.dividerColor)),
                      leading: Icon(CupertinoIcons.exclamationmark_triangle_fill, color: a.severity == 'critical' ? AppTheme.neonRed : AppTheme.neonOrange),
                      title: Text(a.title, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: Text(a.time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricCard(String title, double val, String suffix, IconData icon, Color color, ThemeData theme, {int decimals = 0, bool isCompact = false, double maxVal = 100.0}) {
    return GlowingCard(
      glowColor: color, padding: EdgeInsets.all(isCompact ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: isCompact ? 40 : 48,
                height: isCompact ? 40 : 48,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      duration: const Duration(seconds: 1),
                      curve: Curves.easeOutExpo,
                      tween: Tween<double>(begin: 0.0, end: (val / maxVal).clamp(0.0, 1.0)),
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value,
                        backgroundColor: color.withValues(alpha: 0.1),
                        color: color,
                        strokeWidth: 3,
                      ),
                    ),
                    Icon(icon, color: color, size: isCompact ? 20 : 24),
                  ],
                ),
              ),
              Icon(CupertinoIcons.arrow_up_right, color: Colors.grey.withValues(alpha: 0.5), size: 16),
            ],
          ),
          SizedBox(height: isCompact ? 16 : 24),
          Text(title, style: TextStyle(color: Colors.grey, fontSize: isCompact ? 12 : 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 500), curve: Curves.easeOutExpo, tween: Tween<double>(begin: 0.0, end: val),
            builder: (context, value, _) => Text("${value.toStringAsFixed(decimals)}$suffix", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: isCompact ? 24 : 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, String label, bool active, {bool warning = false}) {
    Color color = warning ? AppTheme.neonOrange : (active ? AppTheme.neonGreen : Colors.grey);
    return InkWell(
      onTap: () => _showDiagnosticDialog(context, label, !warning),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1), 
          borderRadius: BorderRadius.circular(12), 
          border: Border.all(color: color.withValues(alpha: 0.4)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 12, spreadRadius: 1)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(warning ? CupertinoIcons.exclamationmark_triangle_fill : (active ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.xmark_circle_fill), color: color, size: 18), 
            const SizedBox(width: 8), 
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold))
          ],
        ),
      ),
    );
  }

  LineChartData _buildChartData(List<SensorData> history, ThemeData theme) {
    List<FlSpot> tempSpots = [], coSpots = [];
    for (int i = 0; i < history.length; i++) {
      tempSpots.add(FlSpot(i.toDouble(), history[i].temperatureC ?? 0.0));
      coSpots.add(FlSpot(i.toDouble(), (history[i].mq2V ?? 0.0) * 10)); 
    }
    return LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (spot) => theme.cardColor.withValues(alpha: 0.9),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final isTemp = spot.barIndex == 0;
              final val = isTemp ? spot.y.toStringAsFixed(1) : (spot.y / 10).toStringAsFixed(2);
              return LineTooltipItem('${isTemp ? "Temp" : "CO"}: $val${isTemp ? "°C" : "V"}', TextStyle(color: isTemp ? AppTheme.neonOrange : AppTheme.neonRed, fontWeight: FontWeight.bold));
            }).toList();
          },
        ),
      ),
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (val) => FlLine(color: theme.dividerColor.withValues(alpha: 0.5), strokeWidth: 1, dashArray: [5, 5])),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (val, _) => Text(val.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 11)))),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: tempSpots, isCurved: true, color: AppTheme.neonOrange, barWidth: 4, dotData: const FlDotData(show: false), 
          belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [AppTheme.neonOrange.withValues(alpha: 0.3), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter))
        ),
        LineChartBarData(
          spots: coSpots, isCurved: true, color: AppTheme.neonRed, barWidth: 4, dotData: const FlDotData(show: false), 
          belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [AppTheme.neonRed.withValues(alpha: 0.3), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter))
        ),
      ],
    );
  }
}

// ==========================================
// TAB 2: MONITOR (ANALYTICS & CSV EXPORT)
// ==========================================
class MonitorTab extends StatefulWidget {
  const MonitorTab({super.key});
  @override
  State<MonitorTab> createState() => _MonitorTabState();
}

class _MonitorTabState extends State<MonitorTab> {
  int _segIndex = 0;

  void _exportCSV(BuildContext context, ThemeData theme, List<SensorData> history) {
    showModalBottomSheet(
      context: context, backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Export Telemetry Data", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("Select the parameters for your CSV report.", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 24),
            ListTile(title: Text("Date Range", style: TextStyle(color: theme.textTheme.bodyLarge?.color)), trailing: const Text("Current Session", style: TextStyle(color: AppTheme.neonGreen)), tileColor: theme.scaffoldBackgroundColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            const SizedBox(height: 12),
            ListTile(title: Text("Include Sensors", style: TextStyle(color: theme.textTheme.bodyLarge?.color)), trailing: const Text("All (CO, VOC, Temp)", style: TextStyle(color: AppTheme.neonGreen)), tileColor: theme.scaffoldBackgroundColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonGreen, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(CupertinoIcons.share), label: const Text("GENERATE & SHARE CSV", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _generateAndShareCSV(history);
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  void _generateAndShareCSV(List<SensorData> history) {
    if (history.isEmpty) return;
    StringBuffer csv = StringBuffer();
    csv.writeln("Timestamp,Temperature(C),Humidity(%),CO(ppm),VOC(ppm),PM2.5(ug/m3)");
    for (var d in history) {
      csv.writeln("${d.timestamp.toIso8601String()},${d.temperatureC?.toStringAsFixed(2) ?? ''},${d.chamberTempC?.toStringAsFixed(2) ?? ''},${d.mq135V?.toStringAsFixed(2) ?? ''},${d.mq2V?.toStringAsFixed(2) ?? ''}");
    }
    // ignore: deprecated_member_use
    Share.share(csv.toString(), subject: 'Biomass_Telemetry_Export.csv');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSegmentedControl<int>(
                    selectedColor: AppTheme.neonGreen, borderColor: AppTheme.neonGreen, unselectedColor: theme.cardColor, groupValue: _segIndex,
                    children: const {0: Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text("Sensors Log")), 1: Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text("Air Quality"))},
                    onValueChanged: (val) => setState(() => _segIndex = val),
                  ),
                ),
              ),
              Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: _segIndex == 0 ? _buildSensorsView(state, theme) : _buildAirQualityView(state.currentData, theme))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSensorsView(AppStateProvider state, ThemeData theme) {
    final stats = state.getSessionAnalytics();
    final isCompact = MediaQuery.of(context).size.width < 600;
    
    return ListView(
      key: const ValueKey(0), padding: EdgeInsets.only(left: isCompact ? 16 : 24, right: isCompact ? 16 : 24, bottom: 100),
      children: [
        Text("Session Analytics", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 16),
        FluidTileGrid(
          minTileWidth: 200,
          children: [
            _statCard("Peak Temp", "${stats['maxT']} °C", AppTheme.neonOrange, theme),
            _statCard("Peak CO", "${stats['maxCO']} ppm", AppTheme.neonRed, theme),
            _statCard("Avg Temp", "${stats['avgT']} °C", AppTheme.neonOrange, theme),
            _statCard("Avg CO", "${stats['avgCO']} ppm", AppTheme.neonRed, theme),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Sensor Data Log", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
            IconButton(icon: const Icon(CupertinoIcons.arrow_down_doc, color: AppTheme.neonGreen), onPressed: () => _exportCSV(context, theme, state.history), tooltip: "Export CSV"),
          ],
        ),
        const SizedBox(height: 16),
        ...state.history.reversed.map((log) => Container(
          margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: theme.dividerColor)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Telemetry Record", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text("Chamber: ${log.chamberTempC?.toStringAsFixed(1) ?? '--'}°C | MQ2: ${log.mq2V?.toStringAsFixed(2) ?? '--'}V | Temp: ${log.temperatureC?.toStringAsFixed(1) ?? '--'}°C", style: const TextStyle(color: Colors.grey, fontSize: 12))]),
              Text("${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ))
      ],
    );
  }

  Widget _statCard(String title, String val, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: theme.dividerColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(val, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAirQualityView(SensorData data, ThemeData theme) {
    int aqi = (((data.mq135V ?? 0) / 5.0) * 100).toInt();
    bool hazardous = aqi > 100;
    final isCompact = MediaQuery.of(context).size.width < 600;
    Color aqiColor = hazardous ? AppTheme.neonRed : AppTheme.neonGreen;
    
    return ListView(
      key: const ValueKey(1), padding: EdgeInsets.only(left: isCompact ? 16 : 24, right: isCompact ? 16 : 24, bottom: 100),
      children: [
        if (hazardous)
          Container(
            padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(color: AppTheme.neonRed.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.neonRed.withValues(alpha: 0.5))),
            child: const Row(children: [Icon(CupertinoIcons.exclamationmark_triangle_fill, color: AppTheme.neonRed, size: 28), SizedBox(width: 16), Expanded(child: Text("Hazardous threshold crossed. System purge recommended immediately.", style: TextStyle(color: AppTheme.neonRed, fontWeight: FontWeight.bold)))]),
          ),
        Center(
          child: TweenAnimationBuilder<double>(
            duration: const Duration(seconds: 2),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 0, end: (aqi / 200).clamp(0.0, 1.0)),
            builder: (context, val, child) => Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.cardColor.withValues(alpha: 0.5),
                boxShadow: [
                  BoxShadow(color: aqiColor.withValues(alpha: 0.2 + (val * 0.2)), blurRadius: 60, spreadRadius: -10),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 260, height: 260,
                    child: CircularProgressIndicator(
                      value: val,
                      backgroundColor: theme.dividerColor.withValues(alpha: 0.3),
                      color: aqiColor,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text((val * 200).toInt().toString(), style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 80, fontWeight: FontWeight.w900, letterSpacing: -3)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: aqiColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                        child: Text("AQI US", style: TextStyle(color: aqiColor, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 56),
        Text("Pollutant Dispersion Levels", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 24),
        _pollutantBar("MQ135 Gas Voltage", (data.mq135V ?? 0) / 5.0, AppTheme.neonOrange, "${(data.mq135V ?? 0).toStringAsFixed(2)} V", theme),
        const SizedBox(height: 24),
        _pollutantBar("MQ2 Smoke/Gas Voltage", (data.mq2V ?? 0) / 5.0, AppTheme.neonPurple, "${(data.mq2V ?? 0).toStringAsFixed(2)} V", theme),
      ],
    );
  }

  Widget _pollutantBar(String label, double percent, Color color, String valLabel, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)), Text(valLabel, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16))]),
        const SizedBox(height: 12),
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeOutCubic,
          tween: Tween<double>(begin: 0.0, end: percent.clamp(0.0, 1.0)),
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: theme.dividerColor.withValues(alpha: 0.5),
              color: color,
              minHeight: 14,
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// TAB 3: CONTROL (NETWORK, AUDIT LOG & CALIBRATION)
// ==========================================
class ControlTab extends StatelessWidget {
  const ControlTab({super.key});

  void _showEditNodeDialog(BuildContext context, AppStateProvider state, ThemeData theme) {
    final node = state.activeNode;
    final nameCtrl = TextEditingController(text: node.name);
    final ipCtrl = TextEditingController(text: node.ipAddress);
    final macCtrl = TextEditingController(text: node.macAddress);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: Text("Edit Node Configuration", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: "Node Name", labelStyle: const TextStyle(color: Colors.grey)), style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
            const SizedBox(height: 12),
            TextField(controller: ipCtrl, decoration: InputDecoration(labelText: "IP Address", labelStyle: const TextStyle(color: Colors.grey)), style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
            const SizedBox(height: 12),
            TextField(controller: macCtrl, decoration: InputDecoration(labelText: "MAC Address", labelStyle: const TextStyle(color: Colors.grey)), style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              state.updateNode(node, nameCtrl.text, ipCtrl.text, macCtrl.text);
              Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showCalibrationDialog(BuildContext context, String sensor, double currentVal, SettingsProvider settings) {
    double tempVal = currentVal;
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Calibrate $sensor", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Adjust analog ADC voltage offset. Incorrect values may trigger false hardware alarms.", style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 24),
              Text("${tempVal > 0 ? '+' : ''}${tempVal.toStringAsFixed(1)} mV", style: const TextStyle(color: AppTheme.neonBlue, fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              CupertinoSlider(value: tempVal.clamp(-15.0, 15.0), min: -15.0, max: 15.0, activeColor: AppTheme.neonBlue, onChanged: (val) => setDialogState(() => tempVal = val)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () { settings.setMqOffset(tempVal); Navigator.pop(ctx); }, child: const Text("Apply Update")),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);

    final isCompact = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: EdgeInsets.only(left: isCompact ? 16 : 24, right: isCompact ? 16 : 24, top: isCompact ? 16 : 24, bottom: 100),
            children: [
              Text("Network & Hardware Diagnostics", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              FluidTileGrid(
                minTileWidth: 300,
                children: [
                  GlowingCard(
                    glowColor: AppTheme.neonBlue, padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Active Connection", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(CupertinoIcons.settings, size: 18, color: Colors.grey),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _showEditNodeDialog(context, state, theme),
                            )
                          ],
                        ),
                        const SizedBox(height: 16),
                        _infoRow(CupertinoIcons.wifi, "IP Address", state.activeNode.ipAddress, AppTheme.neonBlue, theme),
                        const Divider(height: 24),
                        _infoRow(CupertinoIcons.link, "MAC Address", state.activeNode.macAddress, AppTheme.neonBlue, theme),
                        const Divider(height: 24),
                        _infoRow(CupertinoIcons.waveform_path_ecg, "Signal (RSSI)", "${state.rssi} dBm", state.rssi > -60 ? AppTheme.neonGreen : AppTheme.neonOrange, theme),
                      ],
                    ),
                  ),
                  GlowingCard(
                    glowColor: AppTheme.neonGreen, padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Power Systems", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        _infoRow(CupertinoIcons.bolt_fill, "Main Power", "AC Connected", AppTheme.neonGreen, theme),
                        const Divider(height: 24),
                        _infoRow(CupertinoIcons.battery_100, "Battery Backup", "${state.batteryLevel}% (Charging)", AppTheme.neonGreen, theme),
                        const Divider(height: 24),
                        _infoRow(CupertinoIcons.shield_fill, "Heat Protection", "Active", AppTheme.neonOrange, theme),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              if (state.isAdmin) ...[
                Text("Emergency Control & Local Alerts", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  tileColor: theme.cardColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.dividerColor)),
                  leading: const Icon(Icons.dashboard_outlined, color: AppTheme.neonGreen, size: 28),
                  title: Text("Biomass Monitor Safety Dashboard", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)),
                  subtitle: const Text("Direct ESP32 Sprinkler Control & Danger Alerts", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: const Icon(CupertinoIcons.chevron_right, color: Colors.grey, size: 18),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
                ),
                const SizedBox(height: 24),
                Text("Remote Relays", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                FluidTileGrid(
                  minTileWidth: 200,
                  children: [
                    _relayCard("Purge Fan", Icons.air, AppTheme.neonBlue, true, () => state.sendHardwareCommand('fan', true), theme),
                    _relayCard("Sprinkler", Icons.water_drop, AppTheme.neonRed, false, () => state.sendHardwareCommand('sprinkler', true), theme),
                  ],
                ),
                const SizedBox(height: 40),
                
                Text("Hardware Audit Log", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                Container(
                  height: 150, decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.dividerColor)),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8), itemCount: state.auditLogs.length,
                    itemBuilder: (ctx, i) {
                      final log = state.auditLogs[i];
                      return ListTile(
                        leading: const Icon(CupertinoIcons.text_badge_checkmark, color: AppTheme.neonGreen),
                        title: Text(log.action, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text("User: ${log.user}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        trailing: Text(log.timestamp, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 40),
              ],
              
              Text("Sensor Calibration (Admin Override)", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              if (!state.isAdmin)
                Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.neonRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.neonRed.withValues(alpha: 0.4))), child: const Row(children: [Icon(CupertinoIcons.lock_fill, color: AppTheme.neonRed), SizedBox(width: 16), Expanded(child: Text("Calibration requires Administrator authentication.", style: TextStyle(color: AppTheme.neonRed, fontWeight: FontWeight.bold)))]))
              else ...[
                const Text("Tap a sensor below to apply resistance offsets to the ESP32 microcontroller.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 20),
                _calibTile("MQ-2 (Combustible Gas)", "Offset: ${settings.mqCalibOffset.toStringAsFixed(1)} mV", theme, () => _showCalibrationDialog(context, "MQ-2", settings.mqCalibOffset, settings)),
                const SizedBox(height: 12),
                _calibTile("MQ-135 (Air Quality)", "Offset: 0.0 mV", theme, () => _showCalibrationDialog(context, "MQ-135", 0.0, settings)),
                const SizedBox(height: 12),
                _calibTile("DHT22 (Temperature)", "Offset: -0.5 °C", theme, () {}),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String title, String val, Color color, ThemeData theme) {
    return Row(
      children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 16),
        Expanded(child: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15, fontWeight: FontWeight.bold))),
        Text(val, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    );
  }

  Widget _calibTile(String title, String subtitle, ThemeData theme, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), tileColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.dividerColor)),
      title: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle, style: const TextStyle(color: Colors.grey))),
      trailing: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: theme.scaffoldBackgroundColor, borderRadius: BorderRadius.circular(8)), child: const Icon(CupertinoIcons.slider_horizontal_3, color: AppTheme.neonBlue, size: 20)),
      onTap: onTap,
    );
  }

  Widget _relayCard(String title, IconData icon, Color color, bool isActive, VoidCallback onTap, ThemeData theme) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.1) : theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? color.withValues(alpha: 0.5) : theme.dividerColor, width: isActive ? 2 : 1),
          boxShadow: isActive ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 15)] : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 16, fontWeight: FontWeight.bold))),
            CupertinoSwitch(value: isActive, activeTrackColor: color, onChanged: (val) => onTap()),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// TAB 4: ALERTS
// ==========================================
class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key});
  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final theme = Theme.of(context);
    final isCompact = MediaQuery.of(context).size.width < 600;
    List<AlertItem> filteredAlerts = state.alerts;
    if (_filter != 'All') filteredAlerts = state.alerts.where((a) => a.severity.toLowerCase() == _filter.toLowerCase()).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(isCompact ? 16 : 24),
                child: GlowingCard(
                  glowColor: AppTheme.neonOrange, padding: EdgeInsets.all(isCompact ? 16 : 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Session Summary", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text("${state.alerts.length} alerts today", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonRed.withValues(alpha: 0.1), foregroundColor: AppTheme.neonRed, elevation: 0),
                        onPressed: state.clearAllAlerts, icon: const Icon(CupertinoIcons.trash, size: 18), label: const Text("Clear All", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 24),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSegmentedControl<String>(
                    selectedColor: AppTheme.neonOrange, borderColor: AppTheme.neonOrange, unselectedColor: theme.cardColor, groupValue: _filter,
                    children: const {'All': Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("All")), 'Info': Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("Info")), 'Warning': Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("Warning")), 'Critical': Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("Critical"))},
                    onValueChanged: (val) {
                      setState(() => _filter = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: filteredAlerts.isEmpty 
                  ? const Center(child: Text("No alerts found.", style: TextStyle(color: Colors.grey, fontSize: 16)))
                  : ListView.builder(
                      padding: EdgeInsets.only(left: isCompact ? 16 : 24, right: isCompact ? 16 : 24, bottom: 100),
                      itemCount: filteredAlerts.length,
                      itemBuilder: (ctx, i) {
                        final alert = filteredAlerts[i];
                        Color color = alert.severity == 'critical' ? AppTheme.neonRed : (alert.severity == 'warning' ? AppTheme.neonOrange : AppTheme.neonBlue);
                        IconData icon = alert.severity == 'critical' ? CupertinoIcons.exclamationmark_octagon_fill : (alert.severity == 'warning' ? CupertinoIcons.exclamationmark_triangle_fill : CupertinoIcons.info_circle_fill);

                        return Dismissible(
                          key: Key(alert.id), direction: DismissDirection.endToStart,
                          onDismissed: (_) => state.removeAlert(alert.id),
                          background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), decoration: BoxDecoration(color: AppTheme.neonGreen, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.check, color: Colors.white, size: 32)),
                          child: Card(
                            color: theme.cardColor, margin: const EdgeInsets.only(bottom: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.dividerColor)),
                            child: Padding(
                             padding: const EdgeInsets.all(20),
                             child: Row(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(icon, color: color, size: 24)),
                                 const SizedBox(width: 20),
                                 Expanded(
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(alert.title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15))), Text(alert.time, style: const TextStyle(color: Colors.grey, fontSize: 12))]),
                                       const SizedBox(height: 8),
                                       Text(alert.description, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 13, height: 1.4)),
                                     ],
                                   ),
                                 ),
                               ],
                             ),
                           ),
                         ),
                        );
                      },
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// TAB 5: MORE (SETTINGS & ABOUT CAPSTONE)
// ==========================================
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showAboutDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(CupertinoIcons.info_circle_fill, color: AppTheme.neonBlue),
            const SizedBox(width: 12),
            Text("About the Project", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Design and Evaluation of an IoT-Monitored Low-Emission Biomass Burning System for Controlled Disposal of Backyard Waste", style: TextStyle(color: AppTheme.neonGreen, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text("This system provides real-time telemetry monitoring and automated safety responses for controlled biomass disposal.", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            const Text("Institution:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            Text("Batangas State University JPLPC - Malvar Campus", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 13)),
            const SizedBox(height: 12),
            const Text("Developers:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            Text("Brucal, Cabaluna, Jimenez, Manalo, Vivas", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 13)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close", style: TextStyle(color: AppTheme.neonBlue)))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.select<AppStateProvider, bool>((s) => s.isAdmin);
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);

    final isCompact = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: EdgeInsets.only(left: isCompact ? 16 : 24, right: isCompact ? 16 : 24, top: isCompact ? 16 : 24, bottom: 100),
            children: [
              Text("Preferences (Auto-Saved)", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              GlowingCard(
                glowColor: AppTheme.cardBorder, padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _switchRow("Dark Mode Theme", settings.isDarkMode, theme, (val) => settings.toggleTheme()),
                    const Divider(height: 32),
                    _switchRow("Push Notifications", settings.pushNotifications, theme, (val) => settings.togglePush(val)),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              Text("Telemetry Connection", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              GlowingCard(
                glowColor: AppTheme.cardBorder, padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Polling Interval", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15, fontWeight: FontWeight.bold)),
                    CupertinoSegmentedControl<int>(
                      selectedColor: AppTheme.neonGreen, borderColor: AppTheme.neonGreen, unselectedColor: theme.cardColor, groupValue: settings.pollingInterval,
                      children: const {1: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("1s")), 2: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("2s")), 5: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("5s"))},
                      onValueChanged: (val) {
                        settings.setPollingInterval(val);
                        context.read<AppStateProvider>().startLiveTelemetryStream(); 
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              Text("Safety Thresholds", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              GlowingCard(
                glowColor: AppTheme.cardBorder, padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _sliderRow("Temp Warning (°C)", settings.tempThreshold, 30.0, 70.0, AppTheme.neonOrange, theme, 
                      (val) => settings.setTempThreshold(val),
                      (val) => context.read<AppStateProvider>().updateEsp32Settings(val, settings.coThreshold)
                    ),
                    const Divider(height: 32),
                    _sliderRow("MQ2 Alert (Volts)", settings.coThreshold, 0.1, 5.0, AppTheme.neonRed, theme, 
                      (val) => settings.setCoThreshold(val),
                      (val) => context.read<AppStateProvider>().updateEsp32Settings(settings.tempThreshold, val)
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              if (isAdmin) ...[
                 Text("Admin Security & Access", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
                 const SizedBox(height: 16),
                 GlowingCard(
                   glowColor: AppTheme.cardBorder, padding: const EdgeInsets.all(24),
                   child: Column(
                     children: [
                       _switchRow("Biometric Login (Face ID)", settings.biometricLogin, theme, (val) => settings.toggleBiometric(val)),
                       const Divider(height: 32),
                       Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [Text("Session Timeout", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15, fontWeight: FontWeight.bold)), const Text("30 mins", style: TextStyle(color: Colors.grey, fontSize: 15))],
                       ),
                     ],
                   ),
                 ),
                 const SizedBox(height: 32),
              ],

              GlowingCard(
                glowColor: AppTheme.cardBorder, padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Material(type: MaterialType.transparency, child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), leading: const Icon(CupertinoIcons.info_circle_fill, color: AppTheme.neonBlue), title: Text("About / Documentation", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)), trailing: const Icon(CupertinoIcons.chevron_right, color: Colors.grey, size: 18), onTap: () => _showAboutDialog(context, theme))),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sliderRow(String label, double val, double min, double max, Color color, ThemeData theme, Function(double) onChanged, [Function(double)? onChangeEnd]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(label, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15, fontWeight: FontWeight.bold))), Text(val.toStringAsFixed(1), style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 12),
        CupertinoSlider(value: val.clamp(min, max), min: min, max: max, activeColor: color, onChanged: onChanged, onChangeEnd: onChangeEnd),
      ],
    );
  }

  Widget _switchRow(String label, bool val, ThemeData theme, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Expanded(child: Text(label, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15, fontWeight: FontWeight.bold))), CupertinoSwitch(value: val, activeTrackColor: AppTheme.neonGreen, onChanged: onChanged)],
    );
  }
}

// ==========================================
// ROOT APPLICATION ENTRY
// ==========================================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return MaterialApp(
      title: 'Biomass IoT Monitor',
      debugShowCheckedModeBanner: false,
      theme: settings.isDarkMode ? AppTheme.getDarkTheme() : AppTheme.getLightTheme(),
      home: Consumer<AppStateProvider>(builder: (context, state, _) => state.isAuthenticated ? const MainWrapper() : const LoginScreen()),
      routes: {
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}