import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/features/safety/control_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('does not expose audit logs or sensor calibration controls', (
    tester,
  ) async {
    databaseFactoryOrNull ??= databaseFactorySqflitePlugin;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => '/tmp/biomass-tests',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.tekartik.sqflite'),
      (call) async => switch (call.method) {
        'openDatabase' => {'id': 1},
        'query' => <Map<String, Object?>>[],
        _ => null,
      },
    );
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final appState = AppStateProvider(
      preferences,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(appState.dispose);
    expect(await appState.login('admin', 'password'), isTrue);

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: appState)],
        child: const MaterialApp(home: ControlTab()),
      ),
    );

    expect(find.text('Hardware Audit Log'), findsNothing);
    expect(find.text('Sensor Calibration (Admin Override)'), findsNothing);
    appState.logout();
  });
}
