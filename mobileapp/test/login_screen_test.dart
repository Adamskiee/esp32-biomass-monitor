import 'dart:async';
import 'dart:convert';

import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/features/authentication/login_screen.dart';
import 'package:biomass_iot_app/features/settings/settings_controller.dart';
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
  setUp(() {
    databaseFactoryOrNull = databaseFactorySqflitePlugin;
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
        'query' =>
          (call.arguments as Map)['sql'] == 'PRAGMA user_version'
              ? [
                  {'user_version': 2},
                ]
              : <Map<String, Object?>>[],
        _ => null,
      },
    );
  });

  testWidgets('login fields fit within a 320 pixel wide phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final state = AppStateProvider(prefs);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => SettingsController(prefs)),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    final viewport = tester.getRect(find.byType(Scaffold));
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    for (final field in fields.evaluate()) {
      final bounds = tester.getRect(find.byWidget(field.widget));
      expect(bounds.left, greaterThanOrEqualTo(viewport.left));
      expect(bounds.right, lessThanOrEqualTo(viewport.right));
      expect(bounds.width, greaterThanOrEqualTo(240));
    }
    final connectionButton = find.byType(ElevatedButton);
    await tester.ensureVisible(connectionButton);
    await tester.pump();
    final buttonBounds = tester.getRect(connectionButton);
    expect(buttonBounds.top, greaterThanOrEqualTo(24));
    expect(buttonBounds.bottom, lessThanOrEqualTo(viewport.bottom - 24));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('login preserves the desktop gap before the connection button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final state = AppStateProvider(prefs);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => SettingsController(prefs)),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    final passcodeBounds = tester.getRect(find.byType(TextField).at(2));
    final buttonBounds = tester.getRect(find.byType(ElevatedButton));
    expect(buttonBounds.top - passcodeBounds.bottom, closeTo(40, 0.1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final scenario in [
    (
      name: 'unauthorized',
      status: 401,
      message: 'Invalid username or password.',
    ),
    (
      name: 'busy',
      status: 503,
      message: 'Device is busy. Wait a moment and try again.',
    ),
    (
      name: 'server error',
      status: 500,
      message: 'Device returned an unexpected response (HTTP 500).',
    ),
    (
      name: 'network error',
      status: null,
      message:
          'Cannot reach the device. Check its IP address and Wi-Fi connection.',
    ),
  ]) {
    testWidgets(
      'login explains ${scenario.name} without exposing credentials',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final logs = <String>[];
        final originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        addTearDown(() => debugPrint = originalDebugPrint);
        final client = MockClient((request) async {
          if (scenario.status == null) {
            throw http.ClientException(
              'sensitive-passcode Authorization Basic raw-error',
            );
          }
          return http.Response('sensitive-response-body', scenario.status!);
        });
        final state = AppStateProvider(prefs, client: client);
        addTearDown(state.dispose);
        addTearDown(client.close);
        await state.saveDeviceIp('192.168.1.42');
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: state),
              ChangeNotifierProvider(create: (_) => SettingsController(prefs)),
            ],
            child: const MaterialApp(home: LoginScreen()),
          ),
        );
        await tester.enterText(
          find.byType(TextField).at(1),
          'private-operator',
        );
        await tester.enterText(
          find.byType(TextField).at(2),
          'sensitive-passcode',
        );
        await tester.ensureVisible(find.byType(ElevatedButton));
        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();
        debugPrint = originalDebugPrint;
        expect(find.text(scenario.message), findsOneWidget);
        expect(state.isAuthenticated, isFalse);
        final diagnostic = logs
            .where((line) => line.startsWith('Device login:'))
            .single;
        expect(diagnostic, contains('elapsed_ms='));
        expect(
          diagnostic,
          contains(
            scenario.status == null
                ? 'ClientException'
                : 'status=${scenario.status}',
          ),
        );
        for (final sensitive in [
          'private-operator',
          'sensitive-passcode',
          'sensitive-response-body',
          'Authorization',
          'Basic',
          'raw-error',
          base64Encode(utf8.encode('private-operator:sensitive-passcode')),
        ]) {
          expect(diagnostic, isNot(contains(sensitive)));
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'login reports the actual request timeout and a retry can succeed',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final pending = Completer<http.Response>();
      var attempts = 0;
      final client = MockClient((_) {
        attempts++;
        return attempts == 1
            ? pending.future
            : Future.value(http.Response('{}', 200));
      });
      final state = AppStateProvider(prefs, client: client);
      addTearDown(state.dispose);
      addTearDown(client.close);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(create: (_) => SettingsController(prefs)),
          ],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField).at(0), '192.168.1.42');
      await tester.enterText(find.byType(TextField).at(2), 'secret');
      await tester.ensureVisible(find.byType(ElevatedButton));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(
        find.text(
          'Connection timed out after 3 seconds. Wait a moment and try again.',
        ),
        findsOneWidget,
      );
      expect(state.isAuthenticated, isFalse);
      expect(attempts, 1);
      pending.complete(http.Response('{}', 200));
      await tester.pump();
      expect(state.isAuthenticated, isFalse);
      await tester.ensureVisible(find.byType(ElevatedButton));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(state.isAuthenticated, isTrue);
      state.logout();
      expect(
        find.text(
          'Connection timed out after 3 seconds. Wait a moment and try again.',
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
