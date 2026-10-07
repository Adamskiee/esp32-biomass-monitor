import 'dart:async';
import 'dart:convert';

import 'package:biomass_iot_app/main.dart';
import 'package:fl_chart/fl_chart.dart';
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

  late AppStateProvider state;
  late MockClient client;
  late SharedPreferences prefs;
  var temperature = 26.5;

  setUp(() async {
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
        'query' =>
          (call.arguments as Map)['sql'] == 'PRAGMA user_version'
              ? [
                  {'user_version': 2},
                ]
              : <Map<String, Object?>>[],
        'insert' => 1,
        _ => null,
      },
    );
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    temperature = 26.5;
    client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'temperature_c': temperature,
          'chamber_temp_c': 65.4,
          'mq135_v': 0.75,
          'mq2_v': 1.25,
          'fan_on': false,
          'sprinkler_on': false,
          'active_triggers': [],
        }),
        200,
      ),
    );
  });

  Future<void> initialize(WidgetTester tester) async {
    state = AppStateProvider(prefs, client: client);
    state.setLoginNodeIp('192.168.1.42');
    await tester.pump();
  }

  Future<void> mount(
    WidgetTester tester, {
    Widget child = const MainWrapper(),
    Size size = const Size(450, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(home: child),
      ),
    );
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    client.close();
  }

  testWidgets('mobile navigation has no backdrop blur', (tester) async {
    await initialize(tester);
    await mount(tester);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(
      find.descendant(
        of: find.byWidget(scaffold.bottomNavigationBar!),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
    await dispose(tester);
  });

  testWidgets('desktop navigation uses the sidebar', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    // Navigation assertions do not need the sidebar's remote font download.
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final asset = utf8.decode(message!.buffer.asUint8List());
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage({
          'Inter-Bold.ttf': [
            {'asset': 'Inter-Bold.ttf'},
          ],
        });
      }
      if (asset == 'Inter-Bold.ttf') return ByteData(0);
      return null;
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    await initialize(tester);
    await mount(tester, size: const Size(1200, 900));
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.text('Home Dashboard'), findsOneWidget);
    expect(find.text('Air Quality Monitor'), findsOneWidget);
    expect(find.text('System Control'), findsOneWidget);
    expect(find.text('Active Alerts'), findsOneWidget);
    expect(find.text('Settings & Admin'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('Monitor remains selected through the tab transition', (
    tester,
  ) async {
    await initialize(tester);
    await mount(tester);
    await tester.tap(find.text('Monitor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      1,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      1,
    );
    expect(find.byType(MonitorTab), findsOneWidget);
    expect(find.byType(HomeTab), findsNothing);
    await dispose(tester);
  });

  testWidgets(
    'telemetry arriving during a transition preserves Monitor selection',
    (tester) async {
      await initialize(tester);
      expect(await state.login('operator', 'secret'), isTrue);
      await mount(tester);
      await tester.pump(const Duration(milliseconds: 1850));
      await tester.tap(find.text('Monitor'));
      await tester.pump();
      await tester.tap(find.text('Air Quality'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(state.telemetryRevision, 1);
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        1,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(MonitorTab), findsOneWidget);
      expect(find.byType(HomeTab), findsNothing);
      await dispose(tester);
    },
  );

  testWidgets('Home renders the latest sensor value and live history', (
    tester,
  ) async {
    await initialize(tester);
    expect(await state.login('operator', 'secret'), isTrue);
    await mount(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('26.5 °C'), findsOneWidget);
    temperature = 29.5;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('29.5 °C'), findsOneWidget);
    expect(find.text('26.5 °C'), findsNothing);
    await tester.scrollUntilVisible(find.byType(LineChart), 150);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.first.spots, const [
      FlSpot(0, 26.5),
      FlSpot(1, 29.5),
    ]);
    await dispose(tester);
  });

  testWidgets('Home resumes telemetry after a completed tab round trip', (
    tester,
  ) async {
    await initialize(tester);
    expect(await state.login('operator', 'secret'), isTrue);
    await mount(tester, size: const Size(800, 900));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('26.5 °C'), findsOneWidget);
    final originalHomeState = tester.state(find.byType(HomeTab));

    await tester.tap(find.text('Monitor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.byType(MonitorTab), findsOneWidget);
    expect(find.byType(HomeTab), findsNothing);
    expect(originalHomeState.mounted, isFalse);

    await tester.tap(find.text('Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.byType(MonitorTab), findsNothing);
    expect(find.byType(HomeTab), findsOneWidget);
    final returnedHomeState = tester.state(find.byType(HomeTab));
    expect(returnedHomeState, isNot(same(originalHomeState)));
    expect(returnedHomeState.mounted, isTrue);

    final revisionBeforeSample = state.telemetryRevision;
    temperature = 29.5;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.telemetryRevision, greaterThan(revisionBeforeSample));
    expect(find.text('29.5 °C'), findsOneWidget);
    expect(find.text('26.5 °C'), findsNothing);
    expect(tester.state(find.byType(HomeTab)), same(returnedHomeState));
    await dispose(tester);
  });

  testWidgets('successful telemetry leaves shell navigation widgets intact', (
    tester,
  ) async {
    await initialize(tester);
    expect(await state.login('operator', 'secret'), isTrue);
    await mount(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    final navigation = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    temperature = 29.5;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(
      tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)),
      same(navigation),
    );
    await dispose(tester);
  });

  testWidgets('Home ignores changes to the selected tab value', (tester) async {
    await initialize(tester);
    expect(await state.login('operator', 'secret'), isTrue);
    await mount(tester, child: const HomeTab());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    final metric = tester.widget<SensorMetricCard>(
      find.byType(SensorMetricCard).first,
    );
    state.setTab(1);
    await tester.pump();
    expect(
      tester.widget<SensorMetricCard>(find.byType(SensorMetricCard).first),
      same(metric),
    );
    await dispose(tester);
  });

  testWidgets('Home renders history loaded after its first build', (
    tester,
  ) async {
    final storedHistory = Completer<List<Map<String, Object?>>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'), (
          call,
        ) async {
          if (call.method == 'openDatabase') return {'id': 1};
          if (call.method != 'query') return null;
          final sql = (call.arguments as Map)['sql'] as String;
          if (sql == 'PRAGMA user_version') {
            return [
              {'user_version': 2},
            ];
          }
          if (sql.contains('sensor_data')) return storedHistory.future;
          return <Map<String, Object?>>[];
        });
    await initialize(tester);
    await mount(tester, child: const HomeTab());
    await tester.scrollUntilVisible(
      find.text('No historical data available'),
      150,
    );

    storedHistory.complete([
      {
        'temperature_c': 26.5,
        'chamber_temp_c': 65.4,
        'mq135_v': 0.75,
        'mq2_v': 1.25,
        'timestamp': '2026-10-07T08:00:00.000',
      },
    ]);
    await tester.pump();
    await tester.pump();
    expect(state.telemetryRevision, 0);
    expect(state.history, hasLength(1));
    expect(find.byType(LineChart), findsOneWidget);
    await dispose(tester);
  });
}
