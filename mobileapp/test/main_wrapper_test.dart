import 'dart:async';
import 'dart:convert';

import 'package:biomass_iot_app/app/app_shell.dart';
import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/features/monitoring/home_tab.dart';
import 'package:biomass_iot_app/features/monitoring/monitor_tab.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/widgets/sensor_metric_card.dart';
import 'package:biomass_iot_app/features/safety/widgets/safety_controls_panel.dart';
import 'package:biomass_iot_app/features/safety/control_tab.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fl_chart/src/chart/line_chart/line_chart_renderer.dart';
import 'package:flutter/cupertino.dart';
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
  double? temperature = 26.5;
  double? humidity = 54.5;
  double? chamber = 65.4;
  double? mq135 = 0.75;
  double? mq2 = 1.25;
  double? pm1 = 8.0;
  double? pm25 = 12.0;
  double? pm10 = 18.0;

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
    humidity = 54.5;
    chamber = 65.4;
    mq135 = 0.75;
    mq2 = 1.25;
    pm1 = 8.0;
    pm25 = 12.0;
    pm10 = 18.0;
    client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'temperature_c': temperature,
          'humidity_percent': humidity,
          'chamber_temp_c': chamber,
          'mq135_v': mq135,
          'mq2_v': mq2,
          'pm1_0_ug_m3': pm1,
          'pm2_5_ug_m3': pm25,
          'pm10_ug_m3': pm10,
          'pump_on': false,
          'threshold_chamber_temp_c': 70,
          'threshold_mq2_v': 2.5,
          'threshold_mq135_v': null,
          'threshold_temperature_c': null,
          'threshold_pm1_0_ug_m3': null,
          'threshold_pm2_5_ug_m3': null,
          'threshold_pm10_ug_m3': null,
          'threshold_humidity_min_percent': null,
          'threshold_humidity_max_percent': null,
          'active_triggers': [],
        }),
        200,
      ),
    );
  });

  Future<void> initialize(WidgetTester tester) async {
    state = AppStateProvider(prefs, client: client);
    await state.saveDeviceIp('192.168.1.42');
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

  testWidgets('non-admin Control hides diagnostics and safety controls', (
    tester,
  ) async {
    await initialize(tester);
    await mount(tester, child: const ControlTab());
    expect(find.text('IP Address'), findsNothing);
    expect(find.text('Emergency Control & Local Alerts'), findsNothing);
    expect(find.byType(SafetyControlsPanel), findsNothing);
    await dispose(tester);
  });

  testWidgets(
    'authenticated Control embeds all thresholds and retains service during telemetry rebuilds',
    (tester) async {
      await initialize(tester);
      expect(await state.login('operator', 'secret'), isTrue);
      await mount(tester);
      await tester.tap(find.text('Control'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Emergency Control & Local Alerts'), findsOneWidget);
      expect(find.text('EcoBurn Safety Dashboard'), findsNothing);
      expect(find.text('IP Address'), findsNothing);
      final panel = find.byType(SafetyControlsPanel);
      final api = tester.widget<SafetyControlsPanel>(panel).apiService;
      expect(find.byType(TextFormField), findsNothing);
      final header = find.byKey(
        const ValueKey('threshold_chamber_temp_c_header'),
      );
      await tester.ensureVisible(header);
      await tester.tap(header);
      await tester.pump();
      final input = find.byKey(const ValueKey('threshold_chamber_temp_c'));
      await tester.ensureVisible(input);
      await tester.enterText(input, '85');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(
        identical(tester.widget<SafetyControlsPanel>(panel).apiService, api),
        isTrue,
      );
      expect(tester.widget<TextFormField>(input).controller!.text, '85');
      await tester.ensureVisible(find.text('Apply Thresholds'));
      expect(find.text('Apply Thresholds'), findsOneWidget);
      await dispose(tester);
    },
  );

  testWidgets('desktop navigation uses the sidebar', (tester) async {
    await initialize(tester);
    await mount(tester, size: const Size(1200, 900));
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.text('ECOBURN'), findsOneWidget);
    expect(find.text('Home Dashboard'), findsOneWidget);
    expect(find.text('Air Quality Monitor'), findsOneWidget);
    expect(find.text('System Control'), findsOneWidget);
    expect(find.text('Active Alerts'), findsOneWidget);
    expect(find.text('Settings & Admin'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('mobile header displays the EcoBurn icon', (tester) async {
    await initialize(tester);
    await mount(tester);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/ecoburn-icon.png',
      ),
      findsOneWidget,
    );

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

  testWidgets('Home renders all live telemetry trend groups', (tester) async {
    await initialize(tester);
    expect(await state.login('operator', 'secret'), isTrue);
    await mount(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('26.5 °C'), findsOneWidget);
    expect(find.text('54.5 %'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SensorMetricCard),
        matching: find.text('PM1.0'),
      ),
      findsOneWidget,
    );
    expect(find.text('8.0 µg/m³'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SensorMetricCard),
        matching: find.text('PM2.5'),
      ),
      findsOneWidget,
    );
    expect(find.text('12.0 µg/m³'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SensorMetricCard),
        matching: find.text('PM10'),
      ),
      findsOneWidget,
    );
    expect(find.text('18.0 µg/m³'), findsOneWidget);
    temperature = 29.5;
    humidity = 56.0;
    mq135 = 0.95;
    mq2 = 1.55;
    pm1 = 9.0;
    pm25 = 13.0;
    pm10 = 19.0;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('29.5 °C'), findsOneWidget);
    expect(find.text('26.5 °C'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Real-Time Telemetry Trends'),
      150,
    );
    expect(find.byType(LineChart), findsNWidgets(4));
    final charts = tester
        .widgetList<LineChart>(find.byType(LineChart))
        .toList();
    expect(charts[0].data.lineBarsData.first.spots, const [
      FlSpot(0, 26.5),
      FlSpot(1, 29.5),
    ]);
    expect(charts[0].data.lineBarsData, hasLength(2));
    expect(charts[1].data.lineBarsData, hasLength(2));
    expect(charts[2].data.lineBarsData, hasLength(1));
    expect(charts[3].data.lineBarsData, hasLength(3));
    expect(charts[1].data.lineBarsData[0].spots, const [
      FlSpot(0, 1.25),
      FlSpot(1, 1.55),
    ]);
    expect(charts[1].data.lineBarsData[1].spots, const [
      FlSpot(0, 0.75),
      FlSpot(1, 0.95),
    ]);
    expect(charts[2].data.lineBarsData[0].spots, const [
      FlSpot(0, 54.5),
      FlSpot(1, 56),
    ]);
    expect(charts[3].data.lineBarsData[0].spots, const [
      FlSpot(0, 8),
      FlSpot(1, 9),
    ]);
    expect(charts[3].data.lineBarsData[1].spots, const [
      FlSpot(0, 12),
      FlSpot(1, 13),
    ]);
    expect(charts[3].data.lineBarsData[2].spots, const [
      FlSpot(0, 18),
      FlSpot(1, 19),
    ]);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Gas Sensors'), findsOneWidget);
    expect(find.text('Particulate Matter'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('Home shows the critical alert icon for gas hazards', (
    tester,
  ) async {
    await initialize(tester);
    await state.alertsController.recordTriggers(
      SensorData(timestamp: DateTime.now(), mq2V: 1.25),
      ['high_mq2_gas'],
    );
    await mount(tester);

    expect(
      find.byIcon(CupertinoIcons.exclamationmark_octagon_fill),
      findsOneWidget,
    );
    expect(
      find.byIcon(CupertinoIcons.exclamationmark_triangle_fill),
      findsNothing,
    );

    await dispose(tester);
  });

  testWidgets('Home shows unavailable particulate readings as chart gaps', (
    tester,
  ) async {
    await initialize(tester);
    expect(await state.login('operator', 'secret'), isTrue);
    await mount(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    pm1 = null;
    pm25 = null;
    pm10 = null;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    pm1 = 9.0;
    pm25 = 13.0;
    pm10 = 19.0;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Real-Time Telemetry Trends'),
      150,
    );
    final particulateChart = tester
        .widgetList<LineChart>(find.byType(LineChart))
        .toList()[3];
    expect(particulateChart.data.lineBarsData[0].spots, const [
      FlSpot(0, 8),
      FlSpot.nullSpot,
      FlSpot(2, 9),
    ]);
    expect(particulateChart.data.lineBarsData[1].spots, const [
      FlSpot(0, 12),
      FlSpot.nullSpot,
      FlSpot(2, 13),
    ]);
    expect(particulateChart.data.lineBarsData[2].spots, const [
      FlSpot(0, 18),
      FlSpot.nullSpot,
      FlSpot(2, 19),
    ]);
    await dispose(tester);
  });

  for (final scenario in [
    (
      missing: 'chamber',
      ambient: 26.5,
      chamber: null,
      spot: const FlSpot(0, 26.5),
      tooltip: 'Ambient: 26.5 °C',
    ),
    (
      missing: 'ambient',
      ambient: null,
      chamber: 65.4,
      spot: const FlSpot(0, 65.4),
      tooltip: 'Chamber: 65.4 °C',
    ),
  ]) {
    testWidgets('Home handles unavailable ${scenario.missing} readings', (
      tester,
    ) async {
      await initialize(tester);
      temperature = scenario.ambient;
      chamber = scenario.chamber;
      expect(await state.login('operator', 'secret'), isTrue);
      await mount(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Real-Time Telemetry Trends'),
        150,
      );
      final chart = tester.widget<LineChart>(find.byType(LineChart).first);
      expect(chart.data.lineBarsData, hasLength(1));
      final bar = chart.data.lineBarsData.single;
      expect(bar.spots, [scenario.spot]);
      final tooltips = chart.data.lineTouchData.touchTooltipData
          .getTooltipItems([LineBarSpot(bar, 0, scenario.spot)]);
      expect(tooltips.single!.text, scenario.tooltip);
      expect(tester.takeException(), isNull);
      await dispose(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home handles unavailable gas and particulate series', (
    tester,
  ) async {
    await initialize(tester);
    mq2 = null;
    pm25 = null;
    expect(await state.login('operator', 'secret'), isTrue);
    await mount(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Real-Time Telemetry Trends'),
      150,
    );
    final charts = tester
        .widgetList<LineChart>(find.byType(LineChart))
        .toList();
    expect(charts, hasLength(4));
    expect(charts[1].data.lineBarsData.single.spots, const [FlSpot(0, 0.75)]);
    final particulateBars = charts[3].data.lineBarsData;
    expect(particulateBars, hasLength(2));
    expect(particulateBars[0].spots, const [FlSpot(0, 8)]);
    expect(particulateBars[1].spots, const [FlSpot(0, 18)]);
    final tooltips = charts[3].data.lineTouchData.touchTooltipData
        .getTooltipItems([
          LineBarSpot(particulateBars[1], 1, const FlSpot(0, 18)),
        ]);
    expect(tooltips.single!.text, 'PM10: 18.0 µg/m³');
    await dispose(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home handles unavailable charts until zero readings return', (
    tester,
  ) async {
    await initialize(tester);
    temperature = humidity = chamber = mq135 = mq2 = pm1 = pm25 = pm10 = null;
    expect(await state.login('operator', 'secret'), isTrue);
    await mount(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Real-Time Telemetry Trends'),
      150,
    );
    expect(find.byType(LineChart), findsNothing);
    for (final title in [
      'Temperature',
      'Gas Sensors',
      'Humidity',
      'Particulate Matter',
    ]) {
      expect(find.text('No readings available for $title'), findsOneWidget);
    }
    temperature = humidity = chamber = mq135 = mq2 = pm1 = pm25 = pm10 = 0;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(LineChart), findsNWidgets(4));
    for (final chart in tester.widgetList<LineChart>(find.byType(LineChart))) {
      for (final bar in chart.data.lineBarsData) {
        expect(bar.spots, const [FlSpot.nullSpot, FlSpot(1, 0)]);
      }
    }
    expect(find.textContaining('No readings available for'), findsNothing);
    await dispose(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home handles unavailable series while its tooltip is active', (
    tester,
  ) async {
    await initialize(tester);
    expect(await state.login('operator', 'secret'), isTrue);
    await state.pollOnce();
    state.history
      ..clear()
      ..add(
        SensorData(
          temperatureC: 26.5,
          chamberTempC: 65.4,
          timestamp: DateTime.utc(2026, 10, 19),
        ),
      )
      ..addAll(
        List.generate(
          59,
          (index) => SensorData(
            temperatureC: 26.5,
            timestamp: DateTime.utc(2026, 10, 19, 0, 0, index + 1),
          ),
        ),
      );
    chamber = null;
    await mount(tester);
    await tester.scrollUntilVisible(
      find.text('Real-Time Telemetry Trends'),
      150,
    );
    final chartFinder = find.byType(LineChart).first;
    await tester.ensureVisible(chartFinder);
    await tester.pump();
    final chartLeaf = find.descendant(
      of: chartFinder,
      matching: find.byType(LineChartLeaf),
    );
    final chartBounds = tester.getRect(chartLeaf);
    final pointer = await tester.startGesture(
      Offset(chartBounds.left + 2, chartBounds.top + 10),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final touchedSpots = tester
        .widget<LineChartLeaf>(chartLeaf)
        .data
        .showingTooltipIndicators
        .single
        .showingSpots;
    expect(touchedSpots.map((spot) => spot.barIndex), contains(1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<LineChartLeaf>(chartLeaf).data.showingTooltipIndicators,
      isEmpty,
    );
    expect(
      tester.widget<LineChart>(chartFinder).data.lineBarsData,
      hasLength(1),
    );
    await pointer.up();
    chamber = 65.4;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.widget<LineChart>(chartFinder).data.lineBarsData,
      hasLength(2),
    );
    await dispose(tester);
    expect(tester.takeException(), isNull);
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
    expect(find.byType(LineChart), findsNWidgets(2));
    expect(find.text('No readings available for Humidity'), findsOneWidget);
    expect(
      find.text('No readings available for Particulate Matter'),
      findsOneWidget,
    );
    await dispose(tester);
  });
}
