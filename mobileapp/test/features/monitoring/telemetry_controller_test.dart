import 'dart:io';

import 'package:biomass_iot_app/core/device/device_api_client.dart';
import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/authentication/device_address_store.dart';
import 'package:biomass_iot_app/features/authentication/session_controller.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_history_store.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('failed telemetry clears readings and recovery adds history', () async {
    SharedPreferences.setMockInitialValues({});
    var status = 200;
    final client = MockClient(
      (_) async => http.Response(
        status == 200 ? '{"chamber_temp_c": 38.5}' : 'Unavailable',
        status,
      ),
    );
    final session = SessionController(
      DeviceAddressStore(await SharedPreferences.getInstance()),
      clientFactory: (ip, auth) => DeviceApiClient(
        baseUrl: 'http://$ip/api',
        authorizationHeader: auth,
        client: client,
      ),
    );
    await session.login(ipAddress: '192.168.1.2', username: 'a', password: 'b');
    final directory = await Directory.systemTemp.createTemp('telemetry-');
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/db',
    );
    final controller = TelemetryController(
      session,
      SensorHistoryStore(database),
      pollInterval: const Duration(days: 1),
      onReading: (_, _) async {},
    );

    status = 503;
    await controller.pollOnce();
    expect(controller.currentData.chamberTempC, isNull);
    expect(controller.history, isEmpty);
    status = 200;
    await controller.pollOnce();
    expect(controller.isHardwareConnected, isTrue);
    expect(controller.history, hasLength(1));
    await database.close();
    await directory.delete(recursive: true);
  });
}
