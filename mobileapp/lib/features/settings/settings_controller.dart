import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs)
    : _isDarkMode = _prefs.getBool('isDarkMode') ?? true,
      _pushNotifications = _prefs.getBool('pushNotifications') ?? true,
      _biometricLogin = _prefs.getBool('biometricLogin') ?? false,
      _pollingInterval = _prefs.getInt('pollingInterval') ?? 2;

  final SharedPreferences _prefs;
  bool _isDarkMode;
  bool _pushNotifications;
  bool _biometricLogin;
  int _pollingInterval;
  double _mqCalibOffset = 0;

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

  void togglePush(bool value) {
    _pushNotifications = value;
    _prefs.setBool('pushNotifications', value);
    notifyListeners();
  }

  void toggleBiometric(bool value) {
    _biometricLogin = value;
    _prefs.setBool('biometricLogin', value);
    notifyListeners();
  }

  void setMqOffset(double value) {
    _mqCalibOffset = value;
    notifyListeners();
  }

  void setPollingInterval(int value) {
    _pollingInterval = value;
    _prefs.setInt('pollingInterval', value);
    notifyListeners();
  }
}
