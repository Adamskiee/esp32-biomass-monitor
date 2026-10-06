import 'package:biomass_iot_app/features/authentication/device_address_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<DeviceAddressStore> storeWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return DeviceAddressStore(await SharedPreferences.getInstance());
  }

  test('removes malformed legacy nodes without setting an address', () async {
    final store = await storeWith({'savedNodes': 'not json'});

    await store.migrateLegacyNodes();

    expect(store.deviceIp, '');
  });

  test('keeps an existing device address over legacy data', () async {
    final store = await storeWith({
      'deviceIp': '192.168.1.10',
      'savedNodes': '[{"ipAddress":"192.168.1.11"}]',
    });

    await store.migrateLegacyNodes();

    expect(store.deviceIp, '192.168.1.10');
  });

  test('copies the first legacy address and removes saved nodes', () async {
    final store = await storeWith({
      'savedNodes':
          '[{"ipAddress":"192.168.1.11"},{"ipAddress":"192.168.1.12"}]',
    });

    await store.migrateLegacyNodes();

    expect(store.deviceIp, '192.168.1.11');
  });
}
