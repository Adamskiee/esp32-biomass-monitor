import 'dart:convert';

import 'package:biomass_iot_app/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
