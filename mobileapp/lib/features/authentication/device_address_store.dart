import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceAddressStore {
  DeviceAddressStore(this._prefs);

  final SharedPreferences _prefs;

  String get deviceIp => _prefs.getString('deviceIp') ?? '';

  Future<void> saveDeviceIp(String ipAddress) =>
      _prefs.setString('deviceIp', ipAddress.trim());

  Future<void> migrateLegacyNodes() async {
    if (deviceIp.isNotEmpty) {
      await _prefs.remove('savedNodes');
      return;
    }

    final savedNodes = _prefs.getString('savedNodes');
    if (savedNodes == null) return;
    try {
      final nodes = jsonDecode(savedNodes) as List<dynamic>;
      final firstNode = nodes.isEmpty ? null : nodes.first;
      final ipAddress = firstNode is Map<String, dynamic>
          ? (firstNode['ipAddress'] as String? ?? '').trim()
          : '';
      if (ipAddress.isNotEmpty) await saveDeviceIp(ipAddress);
    } on FormatException {
      // Malformed preference data should not prevent login.
    }
    await _prefs.remove('savedNodes');
  }
}
