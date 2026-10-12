import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/features/settings/settings_controller.dart';
import 'package:biomass_iot_app/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the installed app version in the About dialog', (
    tester,
  ) async {
    databaseFactoryOrNull ??= databaseFactorySqflitePlugin;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp/biomass-tests',
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
    PackageInfo.setMockInitialValues(
      appName: 'Biomass Monitor',
      packageName: 'com.biomo.biomassmonitor',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final preferences = await SharedPreferences.getInstance();
    final appState = AppStateProvider(preferences);
    final settings = SettingsController(preferences);
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    await tester.tap(find.text('About / Documentation'));
    await tester.pumpAndSettle();

    expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
  });
}
