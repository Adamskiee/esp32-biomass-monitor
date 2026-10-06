import 'dart:convert';

import 'package:biomass_iot_app/core/device/device_api_client.dart';
import 'package:biomass_iot_app/features/authentication/device_address_store.dart';
import 'package:flutter/foundation.dart';

class SessionController extends ChangeNotifier {
  SessionController(this._addressStore, {required this.clientFactory});

  final DeviceAddressStore _addressStore;
  final DeviceApiClient Function(String ipAddress, String authorizationHeader)
  clientFactory;
  String _username = '';
  String _password = '';
  bool _isAuthenticated = false;
  bool _isAdmin = false;

  String get deviceIp => _addressStore.deviceIp;
  bool get isAuthenticated => _isAuthenticated;
  bool get isAdmin => _isAdmin;
  bool get canResumeWithBiometrics =>
      _username.isNotEmpty && _password.isNotEmpty;

  Future<bool> login({
    required String ipAddress,
    required String username,
    required String password,
  }) async {
    final ip = ipAddress.trim();
    final user = username.trim();
    if (ip.isEmpty || user.isEmpty || password.isEmpty) return false;

    await _addressStore.saveDeviceIp(ip);
    final authorization = _authorizationFor(user, password);
    final client = clientFactory(ip, authorization);
    try {
      await client.fetchState();
    } catch (_) {
      return false;
    } finally {
      client.close();
    }

    _username = user;
    _password = password;
    _isAuthenticated = true;
    _isAdmin = true;
    notifyListeners();
    return true;
  }

  Future<bool> biometricLoginSuccess() {
    if (!canResumeWithBiometrics) return Future.value(false);
    return login(ipAddress: deviceIp, username: _username, password: _password);
  }

  DeviceApiClient createAuthenticatedClient() {
    if (!_isAuthenticated) throw StateError('No authenticated session');
    return clientFactory(deviceIp, _authorizationFor(_username, _password));
  }

  void logout() {
    _isAuthenticated = false;
    _isAdmin = false;
    notifyListeners();
  }

  String _authorizationFor(String username, String password) =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';
}
