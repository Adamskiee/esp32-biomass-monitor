import 'dart:convert';
import 'dart:async';

import 'package:biomass_iot_app/api_service.dart';
import 'package:biomass_iot_app/features/safety/safety_thresholds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<SafetyThresholds> Function(Map<String, double>) updater(
    MockClient client,
  ) => ApiService(
    baseUrl: 'http://device/api',
    authorizationHeader: 'Basic test',
    client: client,
  ).updateSafetyThresholds;

  group('ApiService confirmation', () {
    for (final fallback in [true, false]) {
      test(
        'rejects missing submitted fields with fallback=$fallback',
        () async {
          final update = updater(
            MockClient(
              (request) async => http.Response(
                jsonEncode(
                  request.method == 'POST'
                      ? fallback
                            ? {'status': 'ok'}
                            : {
                                'thresholds': {'threshold_chamber_temp_c': 80},
                              }
                      : {'threshold_chamber_temp_c': 80},
                ),
                200,
              ),
            ),
          );
          await expectLater(
            update({'threshold_temperature_c': 40}),
            throwsException,
          );
        },
      );
    }
    test('fetches old settings confirmation and propagates failure', () async {
      var fail = false;
      final requests = <http.Request>[];
      final update = updater(
        MockClient((request) async {
          requests.add(request);
          return request.method == 'POST'
              ? http.Response('{"status":"ok"}', 200)
              : http.Response(
                  fail ? 'Unavailable' : '{"threshold_temperature_c":40}',
                  fail ? 503 : 200,
                );
        }),
      );
      expect(
        (await update({
          'threshold_temperature_c': 40,
        })).value('threshold_temperature_c'),
        40,
      );
      expect(requests.last.url.path, '/api/settings');
      expect(requests.last.headers['authorization'], 'Basic test');
      fail = true;
      await expectLater(
        update({'threshold_temperature_c': 40}),
        throwsException,
      );
    });
    for (final code in [400, 401, 503]) {
      test('propagates HTTP $code', () async {
        final update = updater(
          MockClient((_) async => http.Response('Rejected', code)),
        );
        await expectLater(
          update({'threshold_temperature_c': 40}),
          throwsException,
        );
      });
    }
    testWidgets('times out threshold writes', (tester) async {
      final pending = Completer<http.Response>();
      final update = updater(MockClient((_) => pending.future));
      final expectation = expectLater(
        update({'threshold_temperature_c': 40}),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump(const Duration(seconds: 3));
      await expectation;
      pending.complete(http.Response('{}', 503));
    });
  });
  test(
    'posts only changed threshold fields and returns nested confirmation',
    () async {
      late http.Request request;
      final service = ApiService(
        baseUrl: 'http://device/api',
        authorizationHeader: 'Basic test',
        client: MockClient((received) async {
          request = received;
          return http.Response(
            jsonEncode({
              'thresholds': {'threshold_temperature_c': 40},
            }),
            200,
          );
        }),
      );

      final confirmed = await service.updateSafetyThresholds({
        'threshold_temperature_c': 40,
      });

      expect(request.headers['authorization'], 'Basic test');
      expect(jsonDecode(request.body), {'threshold_temperature_c': 40});
      expect(confirmed.value('threshold_temperature_c'), 40);
    },
  );
}
