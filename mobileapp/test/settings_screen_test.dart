import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/core/widgets/glowing_card.dart';
import 'package:biomass_iot_app/features/settings/settings_controller.dart';
import 'package:biomass_iot_app/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows grouped support settings without notification controls', (
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
    final preferences = await SharedPreferences.getInstance();
    final appState = AppStateProvider(
      preferences,
      client: MockClient((request) async => http.Response('{}', 200)),
    );
    final settings = SettingsController(preferences);
    addTearDown(appState.dispose);
    expect(await appState.login('admin', 'password'), isTrue);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    expect(find.text('Admin Security & Access'), findsNothing);
    expect(find.text('Biometric Login (Face ID)'), findsNothing);
    expect(find.text('Session Timeout'), findsNothing);
    expect(find.text('Push Notifications'), findsNothing);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Preferences (Auto-Saved)'), findsNothing);
    expect(find.text('Support & Information'), findsOneWidget);
    expect(find.text('About / Documentation'), findsOneWidget);
    expect(find.text('Network & Hardware Diagnostics'), findsOneWidget);
    appState.logout();
  });

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
      appName: 'EcoBurn',
      packageName: 'com.biomo.ecoburn',
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

  testWidgets('reveals connection diagnostics only after they are requested', (
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
    SharedPreferences.setMockInitialValues({'deviceIp': '192.168.1.10'});
    final preferences = await SharedPreferences.getInstance();
    final appState = AppStateProvider(
      preferences,
      client: MockClient((request) async => http.Response('{}', 200)),
    );
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

    expect(find.text('Active Connection'), findsNothing);
    expect(find.text('192.168.1.10'), findsNothing);
    expect(
      find.ancestor(
        of: find.text('Network & Hardware Diagnostics'),
        matching: find.byType(GlowingCard),
      ),
      findsOneWidget,
    );
    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(dividers, hasLength(1));
    expect(dividers.last.indent, 24);
    expect(dividers.last.endIndent, 24);

    await tester.tap(find.text('Network & Hardware Diagnostics'));
    await tester.pumpAndSettle();

    expect(find.text('Active Connection'), findsOneWidget);
    expect(find.text('IP Address'), findsOneWidget);
    expect(find.text('192.168.1.10'), findsOneWidget);
  });
}
