import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://esp32.local/api';
  static http.Client client = http.Client();
  static const Map<String, String> headers = {
    'Content-Type': 'application/json',
    'X-ESP32-Biomass': 'true',
    'Connection': 'close',
  };

  static Future<Map<String, dynamic>> fetchState({http.Client? client}) async {
    final httpClient = client ?? ApiService.client;
    final response = await httpClient
        .get(Uri.parse('$baseUrl/state'), headers: headers)
        .timeout(const Duration(milliseconds: 2000));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load state: ${response.statusCode}');
  }

  static Future<void> setSprinkler(bool state, {http.Client? client}) async {
    final httpClient = client ?? ApiService.client;
    final response = await httpClient
        .post(
          Uri.parse('$baseUrl/control'),
          headers: headers,
          body: jsonEncode({'sprinkler': state}),
        )
        .timeout(const Duration(milliseconds: 2000));
    if (response.statusCode != 200) {
      throw Exception('Failed to set sprinkler: ${response.statusCode}');
    }
  }

  static Future<void> setThresholds(
    double chamberLimit,
    double mq2Limit, {
    http.Client? client,
  }) async {
    final httpClient = client ?? ApiService.client;
    final response = await httpClient
        .post(
          Uri.parse('$baseUrl/thresholds'),
          headers: headers,
          body: jsonEncode({
            'safe_chamber_limit': chamberLimit,
            'safe_mq2_limit': mq2Limit,
          }),
        )
        .timeout(const Duration(milliseconds: 2000));
    if (response.statusCode != 200) {
      throw Exception('Failed to set thresholds: ${response.statusCode}');
    }
  }
}
