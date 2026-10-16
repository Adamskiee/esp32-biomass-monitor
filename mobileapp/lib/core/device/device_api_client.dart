import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:biomass_iot_app/features/safety/safety_thresholds.dart';

class DeviceApiClient {
  DeviceApiClient({
    required String baseUrl,
    required this.authorizationHeader,
    http.Client? client,
  }) : baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String baseUrl;
  final String authorizationHeader;
  final http.Client _client;
  final bool _ownsClient;

  Map<String, String> get _headers => {
    'Authorization': authorizationHeader,
    'Content-Type': 'application/json',
    'Connection': 'close',
  };

  Future<Map<String, dynamic>> fetchState() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/state'), headers: _headers)
        .timeout(const Duration(seconds: 2));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load state: ${response.statusCode}');
  }

  Future<void> setSprinkler(bool state) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/control'),
          headers: _headers,
          body: jsonEncode({'sprinkler': state}),
        )
        .timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) {
      throw Exception('Failed to set sprinkler: ${response.statusCode}');
    }
  }

  Future<void> setThresholds(double chamberLimit, double mq2Limit) async {
    await updateSafetyThresholds({
      'threshold_chamber_temp_c': chamberLimit,
      'threshold_mq2_v': mq2Limit,
    });
  }

  Future<SafetyThresholds> fetchThresholds() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/settings'), headers: _headers)
        .timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) {
      throw Exception('Failed to load thresholds: ${response.statusCode}');
    }
    return SafetyThresholds.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SafetyThresholds> updateSafetyThresholds(
    Map<String, double> changes,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/thresholds'),
          headers: _headers,
          body: jsonEncode(changes),
        )
        .timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) {
      throw Exception('Failed to set thresholds: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final thresholds = body['thresholds'];
    return thresholds is Map<String, dynamic>
        ? SafetyThresholds.fromJson(thresholds)
        : fetchThresholds();
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
