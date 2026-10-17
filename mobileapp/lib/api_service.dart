import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:biomass_iot_app/features/safety/safety_thresholds.dart';

class ApiService {
  ApiService({
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

  void close() {
    if (_ownsClient) _client.close();
  }

  Map<String, String> get headers => {
    'Authorization': authorizationHeader,
    'Content-Type': 'application/json',
    'Connection': 'close',
  };

  Future<Map<String, dynamic>> fetchState() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/state'), headers: headers)
        .timeout(const Duration(milliseconds: 2000));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load state: ${response.statusCode}');
  }

  Future<void> setSprinkler(bool state) async {
    final response = await _client
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

  Future<void> setThresholds(double chamberLimit, double mq2Limit) async {
    await updateSafetyThresholds({
      'threshold_chamber_temp_c': chamberLimit,
      'threshold_mq2_v': mq2Limit,
    });
  }

  Future<SafetyThresholds> fetchThresholds() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/settings'), headers: headers)
        .timeout(const Duration(milliseconds: 2000));
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
          headers: headers,
          body: jsonEncode(changes),
        )
        .timeout(const Duration(milliseconds: 2000));
    if (response.statusCode != 200) {
      throw Exception('Failed to set thresholds: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final thresholds = body['thresholds'];
    final confirmed = thresholds is Map<String, dynamic>
        ? SafetyThresholds.fromJson(thresholds)
        : await fetchThresholds();
    if (changes.keys.any(
      (field) =>
          !confirmed.supports(field) ||
          confirmed.value(field) == null ||
          !confirmed.value(field)!.isFinite,
    )) {
      throw Exception('Device did not confirm every submitted limit.');
    }
    return confirmed;
  }
}
