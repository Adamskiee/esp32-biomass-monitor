import 'dart:convert';

import 'package:biomass_iot_app/core/device/device_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const authorizationHeader = 'Basic YWRtaW46c2VjcmV0';

DeviceApiClient createService(http.Client client) {
  return DeviceApiClient(
    baseUrl: 'http://192.168.1.51/api',
    authorizationHeader: authorizationHeader,
    client: client,
  );
}

void main() {
  test('uses the selected node address and Basic Auth credentials', () async {
    late http.Request recordedRequest;
    final service = createService(
      MockClient((request) async {
        recordedRequest = request;
        return http.Response('{}', 200);
      }),
    );

    await service.fetchState();

    expect(recordedRequest.url, Uri.parse('http://192.168.1.51/api/state'));
    expect(recordedRequest.headers['Authorization'], authorizationHeader);
    expect(recordedRequest.headers['Connection'], 'close');
  });

  group('fetchState', () {
    test('returns the complete state response', () async {
      final service = createService(
        MockClient((request) async {
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode({
              'temperature_c': 28.0,
              'chamber_temp_c': 45.2,
              'mq135_v': 1.4,
              'mq2_v': 1.1,
              'threshold_chamber_temp_c': 60.0,
              'threshold_mq2_v': 1.5,
              'pump_on': false,
              'manual_sprinkler': false,
              'active_triggers': ['high_mq2_gas'],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final state = await service.fetchState();

      expect(state['chamber_temp_c'], 45.2);
      expect(state['pump_on'], isFalse);
      expect(state['active_triggers'], ['high_mq2_gas']);
    });

    test('throws when the ESP32 returns an error', () async {
      final service = createService(
        MockClient((request) async {
          return http.Response('Server Error', 500);
        }),
      );

      expect(service.fetchState, throwsException);
    });
  });

  group('setSprinkler', () {
    test('posts the requested sprinkler state', () async {
      late http.Request recordedRequest;
      final service = createService(
        MockClient((request) async {
          recordedRequest = request;
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }),
      );

      await service.setSprinkler(true);

      expect(recordedRequest.method, 'POST');
      expect(recordedRequest.url, Uri.parse('http://192.168.1.51/api/control'));
      expect(recordedRequest.headers['Authorization'], authorizationHeader);
      expect(jsonDecode(recordedRequest.body), {'sprinkler': true});
    });

    test('throws when safety control rejects the request', () async {
      final service = createService(
        MockClient((request) async {
          return http.Response('Automatic safety control is active', 409);
        }),
      );

      expect(() => service.setSprinkler(false), throwsException);
    });
  });

  group('setThresholds', () {
    test('posts documented threshold fields', () async {
      final requests = <http.Request>[];
      final service = createService(
        MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'threshold_chamber_temp_c': 55.0,
                'threshold_mq2_v': 2.0,
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }),
      );

      await service.setThresholds(55.0, 2.0);

      expect(requests, hasLength(2));
      final recordedRequest = requests.first;
      expect(recordedRequest.method, 'POST');
      expect(
        recordedRequest.url,
        Uri.parse('http://192.168.1.51/api/thresholds'),
      );
      expect(recordedRequest.headers['Authorization'], authorizationHeader);
      expect(jsonDecode(recordedRequest.body), {
        'threshold_chamber_temp_c': 55.0,
        'threshold_mq2_v': 2.0,
      });
      expect(requests.last.method, 'GET');
      expect(requests.last.url.path, '/api/settings');
      expect(requests.last.headers['Authorization'], authorizationHeader);
    });

    test('uses nested confirmed values without fetching settings', () async {
      final requests = <http.Request>[];
      final service = createService(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'status': 'ok',
              'thresholds': {'threshold_mq2_v': 2.0},
            }),
            200,
          );
        }),
      );

      final saved = await service.updateSafetyThresholds({
        'threshold_mq2_v': 2.0,
      });

      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body), {'threshold_mq2_v': 2.0});
      expect(saved.value('threshold_mq2_v'), 2.0);
      expect(saved.supports('threshold_mq135_v'), isFalse);
    });

    test('propagates a failed legacy settings confirmation', () async {
      final service = createService(
        MockClient((request) async {
          return request.method == 'POST'
              ? http.Response('{"status":"ok"}', 200)
              : http.Response('Unavailable', 503);
        }),
      );

      await expectLater(service.setThresholds(55.0, 2.0), throwsException);
    });

    test('throws when threshold validation fails', () async {
      final service = createService(
        MockClient((request) async {
          return http.Response('Invalid threshold', 400);
        }),
      );

      expect(() => service.setThresholds(1000.0, 2.0), throwsException);
    });
  });
}
