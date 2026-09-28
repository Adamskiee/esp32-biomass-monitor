import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:biomass_iot_app/api_service.dart';

void main() {
  group('ApiService configuration', () {
    test('baseUrl matches ESP32 API path', () {
      expect(ApiService.baseUrl, 'http://esp32.local/api');
    });

    test('headers contain required security and connection headers', () {
      expect(ApiService.headers, {
        'Content-Type': 'application/json',
        'X-ESP32-Biomass': 'true',
        'Connection': 'close',
      });
    });
  });

  group('ApiService.fetchState', () {
    test('fetches state successfully with 200 response', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url, Uri.parse('http://esp32.local/api/state'));
        expect(request.headers['X-ESP32-Biomass'], 'true');
        expect(request.headers['Connection'], 'close');
        return http.Response(
          jsonEncode({
            'chamber_temp': 45.2,
            'mq2_v': 1.1,
            'safe_chamber_limit': 60.0,
            'safe_mq2_limit': 1.5,
            'fan_on': true,
            'sprinkler_on': false,
            'manual_sprinkler': false,
            'active_triggers': ['mq2_danger'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final state = await ApiService.fetchState(client: mockClient);
      expect(state['chamber_temp'], 45.2);
      expect(state['active_triggers'], ['mq2_danger']);
    });

    test('throws Exception when fetchState returns non-200', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      expect(() => ApiService.fetchState(client: mockClient), throwsException);
    });
  });

  group('ApiService.setSprinkler', () {
    test('posts sprinkler state true to /control', () async {
      late http.Request recordedRequest;
      final mockClient = MockClient((request) async {
        recordedRequest = request;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      await ApiService.setSprinkler(true, client: mockClient);
      expect(recordedRequest.method, 'POST');
      expect(recordedRequest.url, Uri.parse('http://esp32.local/api/control'));
      expect(recordedRequest.headers['X-ESP32-Biomass'], 'true');
      expect(jsonDecode(recordedRequest.body), {'sprinkler': true});
    });

    test('posts sprinkler state false to /control', () async {
      late http.Request recordedRequest;
      final mockClient = MockClient((request) async {
        recordedRequest = request;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      await ApiService.setSprinkler(false, client: mockClient);
      expect(jsonDecode(recordedRequest.body), {'sprinkler': false});
    });

    test('throws Exception when setSprinkler returns non-200', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Forbidden', 403);
      });

      expect(
        () => ApiService.setSprinkler(true, client: mockClient),
        throwsException,
      );
    });
  });

  group('ApiService.setThresholds', () {
    test('posts thresholds to /thresholds', () async {
      late http.Request recordedRequest;
      final mockClient = MockClient((request) async {
        recordedRequest = request;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      await ApiService.setThresholds(55.0, 2.0, client: mockClient);
      expect(recordedRequest.method, 'POST');
      expect(
        recordedRequest.url,
        Uri.parse('http://esp32.local/api/thresholds'),
      );
      expect(recordedRequest.headers['X-ESP32-Biomass'], 'true');
      expect(jsonDecode(recordedRequest.body), {
        'safe_chamber_limit': 55.0,
        'safe_mq2_limit': 2.0,
      });
    });

    test('throws Exception when setThresholds returns non-200', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Forbidden', 403);
      });

      expect(
        () => ApiService.setThresholds(55.0, 2.0, client: mockClient),
        throwsException,
      );
    });
  });

  group('ApiService default client usage', () {
    test('uses ApiService.client when no client passed', () async {
      final originalClient = ApiService.client;
      try {
        ApiService.client = MockClient((request) async {
          return http.Response(jsonEncode({'test': 123}), 200);
        });
        final result = await ApiService.fetchState();
        expect(result['test'], 123);
      } finally {
        ApiService.client = originalClient;
      }
    });
  });
}
