import 'dart:convert';

import 'package:biomass_iot_app/core/device/device_api_client.dart';
import 'package:biomass_iot_app/features/authentication/device_address_store.dart';
import 'package:biomass_iot_app/features/authentication/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<(SessionController, List<http.Request>)> controllerWithStatus(
    int status,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final requests = <http.Request>[];
    final controller = SessionController(
      DeviceAddressStore(await SharedPreferences.getInstance()),
      clientFactory: (ip, authorization) => DeviceApiClient(
        baseUrl: 'http://$ip/api',
        authorizationHeader: authorization,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', status);
        }),
      ),
    );
    return (controller, requests);
  }

  test('rejected login saves address without authenticating', () async {
    final (controller, requests) = await controllerWithStatus(401);

    expect(
      await controller.login(
        ipAddress: ' 192.168.1.42 ',
        username: 'operator',
        password: 'wrong',
      ),
      isFalse,
    );

    expect(controller.deviceIp, '192.168.1.42');
    expect(controller.isAuthenticated, isFalse);
    expect(requests, hasLength(1));
    expect(() => controller.createAuthenticatedClient(), throwsStateError);
  });

  test(
    'successful login validates Basic Auth and biometric re-entry',
    () async {
      final (controller, requests) = await controllerWithStatus(200);

      expect(
        await controller.login(
          ipAddress: '192.168.1.42',
          username: 'operator',
          password: 'secret',
        ),
        isTrue,
      );
      expect(
        requests.single.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('operator:secret'))}',
      );
      controller.logout();
      expect(await controller.biometricLoginSuccess(), isTrue);
      expect(controller.isAuthenticated, isTrue);
      expect(requests, hasLength(2));
    },
  );
}
