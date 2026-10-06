import 'dart:convert';

import 'package:biomass_iot_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'login accepts device credentials and uses the saved device IP',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{}',
          request.headers['Authorization'] ==
                  'Basic ${base64Encode(utf8.encode('operator:secret'))}'
              ? 200
              : 401,
        );
      });
      final state = AppStateProvider(prefs, client: client);
      await state.saveDeviceIp('192.168.1.42');

      expect(await state.login('operator', 'wrong'), isFalse);
      expect(state.isAuthenticated, isFalse);
      expect(await state.login('operator', 'secret'), isTrue);
      expect(state.isAuthenticated, isTrue);
      expect(requests.last.url.host, '192.168.1.42');

      state.dispose();
      client.close();
    },
  );

  testWidgets('offline polls do not create sensor history', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var online = true;
    final client = MockClient(
      (request) async =>
          http.Response(online ? '{}' : 'Unavailable', online ? 200 : 503),
    );
    final state = AppStateProvider(prefs, client: client);
    await state.saveDeviceIp('192.168.1.42');
    expect(await state.login('operator', 'secret'), isTrue);
    online = false;

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(state.isHardwareConnected, isFalse);
    expect(state.currentData.chamberTempC, isNull);
    expect(state.history, isEmpty);

    state.dispose();
    client.close();
  });
}
