import 'dart:convert';

import 'package:biomass_iot_app/core/networking/device_api_client.dart';
import 'package:biomass_iot_app/core/networking/device_api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const authorizationHeader = 'Basic YWRtaW46c2VjcmV0';

DeviceApiClient createClient(http.Client client) {
  return DeviceApiClient(
    baseUrl: 'http://192.168.1.51/api',
    authorizationHeader: authorizationHeader,
    client: client,
  );
}

void main() {
  test('returns typed device state from a valid response', () async {
    late http.Request request;
    final client = createClient(
      MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'temperature_c': 28.0,
            'chamber_temp_c': 45.2,
            'mq135_v': 1.4,
            'mq2_v': 1.1,
            'threshold_chamber_temp_c': 60.0,
            'threshold_mq2_v': 1.5,
            'fan_on': true,
            'sprinkler_on': false,
            'manual_sprinkler': false,
            'active_triggers': ['high_mq2_gas'],
          }),
          200,
        );
      }),
    );

    final state = await client.fetchState();

    expect(request.url, Uri.parse('http://192.168.1.51/api/state'));
    expect(request.headers['Authorization'], authorizationHeader);
    expect(state.reading.chamberTempC, 45.2);
    expect(state.activeTriggers, ['high_mq2_gas']);
    expect(state.fanOn, isTrue);
  });

  test('maps malformed state data to an invalid response exception', () async {
    final client = createClient(
      MockClient((_) async => http.Response('{"mq2_v":"not-a-number"}', 200)),
    );

    expect(
      client.fetchState,
      throwsA(
        isA<DeviceApiException>().having(
          (error) => error.kind,
          'kind',
          DeviceApiErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('maps a sprinkler safety conflict to a conflict exception', () async {
    final client = createClient(
      MockClient(
        (_) async => http.Response('Automatic safety control is active', 409),
      ),
    );

    expect(
      () => client.setSprinkler(false),
      throwsA(
        isA<DeviceApiException>().having(
          (error) => error.kind,
          'kind',
          DeviceApiErrorKind.safetyConflict,
        ),
      ),
    );
  });

  test('posts documented threshold fields', () async {
    late http.Request request;
    final client = createClient(
      MockClient((value) async {
        request = value;
        return http.Response('{}', 200);
      }),
    );

    await client.setThresholds(55.0, 2.0);

    expect(request.url, Uri.parse('http://192.168.1.51/api/thresholds'));
    expect(jsonDecode(request.body), {
      'threshold_chamber_temp_c': 55.0,
      'threshold_mq2_v': 2.0,
    });
  });
}
