import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/telemetry/sensor_reading.dart';
import 'device_api_exception.dart';

class DeviceState {
  const DeviceState({
    required this.reading,
    required this.fanOn,
    required this.sprinklerOn,
    required this.manualSprinkler,
    required this.chamberTemperatureThreshold,
    required this.mq2Threshold,
    required this.activeTriggers,
  });

  final SensorReading reading;
  final bool fanOn;
  final bool sprinklerOn;
  final bool manualSprinkler;
  final double? chamberTemperatureThreshold;
  final double? mq2Threshold;
  final List<String> activeTriggers;

  factory DeviceState.fromJson(Map<String, dynamic> json, DateTime timestamp) {
    bool boolValue(String key) {
      final value = json[key];
      if (value is! bool) throw FormatException('$key must be boolean');
      return value;
    }

    double? numberValue(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! num) throw FormatException('$key must be numeric');
      return value.toDouble();
    }

    final triggers = json['active_triggers'];
    if (triggers is! List || triggers.any((trigger) => trigger is! String)) {
      throw const FormatException('active_triggers must be a list of strings');
    }

    return DeviceState(
      reading: SensorReading.fromJson(json, timestamp),
      fanOn: boolValue('fan_on'),
      sprinklerOn: boolValue('sprinkler_on'),
      manualSprinkler: boolValue('manual_sprinkler'),
      chamberTemperatureThreshold: numberValue('threshold_chamber_temp_c'),
      mq2Threshold: numberValue('threshold_mq2_v'),
      activeTriggers: List<String>.unmodifiable(triggers.cast<String>()),
    );
  }
}

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

  Map<String, String> get headers => {
    'Authorization': authorizationHeader,
    'Content-Type': 'application/json',
    'Connection': 'close',
  };

  Future<DeviceState> fetchState() async {
    final response = await _request(
      () => _client.get(Uri.parse('$baseUrl/state'), headers: headers),
    );
    _throwForStatus(response);
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('State response must be an object');
      }
      return DeviceState.fromJson(decoded, DateTime.now());
    } on FormatException catch (error) {
      throw DeviceApiException(
        DeviceApiErrorKind.invalidResponse,
        message: error.message.toString(),
      );
    } catch (_) {
      throw const DeviceApiException(DeviceApiErrorKind.invalidResponse);
    }
  }

  Future<void> setSprinkler(bool state) async {
    final response = await _request(
      () => _client.post(
        Uri.parse('$baseUrl/control'),
        headers: headers,
        body: jsonEncode({'sprinkler': state}),
      ),
    );
    _throwForStatus(response);
  }

  Future<void> setThresholds(double chamberLimit, double mq2Limit) async {
    final response = await _request(
      () => _client.post(
        Uri.parse('$baseUrl/thresholds'),
        headers: headers,
        body: jsonEncode({
          'threshold_chamber_temp_c': chamberLimit,
          'threshold_mq2_v': mq2Limit,
        }),
      ),
    );
    _throwForStatus(response);
  }

  Future<http.Response> _request(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(const Duration(milliseconds: 2000));
    } on TimeoutException {
      throw const DeviceApiException(DeviceApiErrorKind.connection);
    } on http.ClientException {
      throw const DeviceApiException(DeviceApiErrorKind.connection);
    }
  }

  void _throwForStatus(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final kind = switch (response.statusCode) {
      401 || 403 => DeviceApiErrorKind.authentication,
      409 => DeviceApiErrorKind.safetyConflict,
      _ => DeviceApiErrorKind.unsuccessfulResponse,
    };
    throw DeviceApiException(kind, statusCode: response.statusCode);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
