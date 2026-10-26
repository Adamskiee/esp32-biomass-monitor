import 'dart:async';
import 'dart:convert';

import 'package:biomass_iot_app/api_service.dart';
import 'package:biomass_iot_app/app/app_icons.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/features/safety/widgets/safety_controls_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const chamber = 'threshold_chamber_temp_c';
const ambient = 'threshold_temperature_c';
const minimum = 'threshold_humidity_min_percent';
const maximum = 'threshold_humidity_max_percent';
Map<String, dynamic> snapshot() => {
  'chamber_temp_c': 50,
  'temperature_c': 25,
  'humidity_percent': 50,
  'mq2_v': 1,
  'mq135_v': 1,
  'pm1_0_ug_m3': 8,
  'pm2_5_ug_m3': 12,
  'pm10_ug_m3': 18,
  'pump_on': false,
  'sprinkler_on': false,
  'active_triggers': <String>[],
  chamber: 70,
  ambient: null,
  'threshold_mq2_v': 5,
  'threshold_mq135_v': null,
  'threshold_pm1_0_ug_m3': null,
  'threshold_pm2_5_ug_m3': null,
  'threshold_pm10_ug_m3': null,
  minimum: 30,
  maximum: 70,
};

void main() {
  Finder input(String key) => find.byKey(ValueKey(key));

  Future<void> openSensor(WidgetTester tester, String field) async {
    final id = field == minimum || field == maximum ? 'humidity_range' : field;
    if (find.byKey(ValueKey(field)).evaluate().isNotEmpty) return;
    final header = find.byKey(ValueKey('${id}_header'));
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pump();
  }

  Future<void> revealInput(WidgetTester tester, String field) async {
    await openSensor(tester, field);
    await tester.ensureVisible(input(field));
  }

  testWidgets(
    'phone slider gesture updates a draft and saves only after Apply',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final state = snapshot();
      final writes = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          final patch = jsonDecode(request.body) as Map<String, dynamic>;
          writes.add(patch);
          state.addAll(patch);
          return http.Response(jsonEncode({'thresholds': state}), 200);
        }
        return http.Response(jsonEncode(state), 200);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SafetyControlsPanel(
                apiService: ApiService(
                  baseUrl: 'http://device/api',
                  authorizationHeader: 'Basic test',
                  client: client,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
      await openSensor(tester, chamber);
      final slider = find.byKey(const ValueKey('${chamber}_slider'));
      await tester.ensureVisible(slider);
      expect(tester.widget<Slider>(slider).value, 70);
      await tester.tapAt(tester.getCenter(slider));
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey(chamber)))
            .controller!
            .text,
        '85',
      );
      expect(writes, isEmpty);

      await tester.ensureVisible(find.text('Apply Thresholds'));
      await tester.tap(find.text('Apply Thresholds'));
      await tester.pump();
      expect(writes, [
        {chamber: 85},
      ]);

      expect(slider, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );
  testWidgets('mute resets after an accepted recovery before retriggering', (
    tester,
  ) async {
    var sounds = 0;
    final state = snapshot()..['active_triggers'] = ['high_pm2_5'];
    final client = MockClient(
      (_) async => http.Response(jsonEncode(state), 200),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SafetyControlsPanel(
              apiService: ApiService(
                baseUrl: 'http://device/api',
                authorizationHeader: 'Basic test',
                client: client,
              ),
              onAlert: () => sounds++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Mute app alerts'));
    state['active_triggers'] = <String>[];
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    state['active_triggers'] = ['high_pm2_5'];
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(sounds, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });
  late Map<String, dynamic> state;
  late List<Map<String, dynamic>> writes;
  late MockClient client;
  late ApiService service;
  setUp(() {
    state = snapshot();
    writes = [];
    client = MockClient((request) async {
      if (request.method == 'POST') {
        final changes = jsonDecode(request.body) as Map<String, dynamic>;
        writes.add(changes);
        state.addAll(changes);
        return http.Response(jsonEncode({'thresholds': state}), 200);
      }
      return http.Response(jsonEncode(state), 200);
    });
  });

  Future<void> mount(
    WidgetTester tester, {
    VoidCallback? onAlert,
    String? openField = chamber,
  }) async {
    service = ApiService(
      baseUrl: 'http://device/api',
      authorizationHeader: 'Basic test',
      client: client,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SafetyControlsPanel(apiService: service, onAlert: onAlert),
          ),
        ),
      ),
    );
    await tester.pump();
    if (openField != null) await openSensor(tester, openField);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(input(key)).controller!.text;
  Future<void> apply(WidgetTester tester) async {
    await tester.pump();
    await tester.ensureVisible(find.text('Apply Thresholds'));
    await tester.tap(find.text('Apply Thresholds'));
    await tester.pump();
  }

  testWidgets(
    'sensors start collapsed and opening another preserves the previous draft',
    (tester) async {
      await mount(tester, openField: null);
      expect(find.byType(Slider, skipOffstage: false), findsNothing);
      expect(find.byType(RangeSlider), findsNothing);
      expect(find.byType(TextFormField, skipOffstage: false), findsNothing);
      expect(find.textContaining('Current:'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      final chamberHeader = find.byKey(const ValueKey('${chamber}_header'));
      await tester.ensureVisible(chamberHeader);
      await tester.tap(chamberHeader);
      await tester.pump();
      expect(find.byType(Slider, skipOffstage: false), findsOneWidget);
      expect(find.byType(TextFormField, skipOffstage: false), findsOneWidget);
      expect(find.text('Current: 50 °C'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
      await tester.enterText(input(chamber), '85');
      final humidityHeader = find.byKey(
        const ValueKey('humidity_range_header'),
      );
      await tester.ensureVisible(humidityHeader);
      await tester.tap(humidityHeader);
      await tester.pump();
      expect(find.byType(Slider, skipOffstage: false), findsNothing);
      expect(find.byType(RangeSlider), findsOneWidget);
      expect(find.byType(TextFormField, skipOffstage: false), findsNWidgets(2));
      expect(find.text('Current: 50 °C'), findsNothing);
      expect(find.text('Current: 50 %'), findsOneWidget);
      await tester.ensureVisible(chamberHeader);
      await tester.tap(chamberHeader);
      await tester.pump();
      expect(find.byType(RangeSlider), findsNothing);
      expect(text(tester, chamber), '85');
      expect(writes, isEmpty);
      await apply(tester);
      expect(writes, [
        {chamber: 85},
      ]);
      expect(find.byType(Slider, skipOffstage: false), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('active alert indicator uses the shared severity colors', (
    tester,
  ) async {
    await mount(tester, openField: null);
    expect(
      tester.widget<Icon>(find.byIcon(AppIcons.alerts)).color,
      AppTheme.successLight,
    );

    state['active_triggers'] = ['high_pm2_5'];
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(
      tester.widget<Icon>(find.byIcon(AppIcons.alerts)).color,
      AppTheme.dangerLight,
    );
    await finish(tester);
  });

  testWidgets('renders sensor summaries before revealing their controls', (
    tester,
  ) async {
    await mount(tester, openField: null);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Current: 25 °C'), findsNothing);
    expect(find.text('Current: 8 µg/m³'), findsNothing);
    expect(find.text('Current: 12 µg/m³'), findsNothing);
    expect(find.text('Current: 18 µg/m³'), findsNothing);
    expect(find.text('Live Sensor Data'), findsNothing);
    expect(find.text('Particulate Matter'), findsOneWidget);
    expect(find.text('Alerts + automatic sprinkler'), findsOneWidget);

    await revealInput(tester, ambient);
    expect(find.text('Current: 25 °C'), findsOneWidget);
    expect(tester.widget<TextFormField>(input(ambient)).enabled, isTrue);
    await finish(tester);
  });

  testWidgets(
    'refreshes saved values while preserving draft and validates latest partner',
    (tester) async {
      await mount(tester);
      await revealInput(tester, minimum);
      await tester.enterText(input(minimum), '35');
      state[maximum] = 34;
      state[chamber] = 90;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(text(tester, minimum), '35');
      expect(text(tester, maximum), '34');
      await openSensor(tester, chamber);
      expect(text(tester, chamber), '90');
      await apply(tester);
      expect(find.byType(RangeSlider), findsOneWidget);
      expect(writes, isEmpty);
      expect(text(tester, minimum), '35');
      await finish(tester);
    },
  );

  testWidgets(
    'Apply reopens an invalid sensor after another sensor was selected',
    (tester) async {
      await mount(tester);
      await tester.enterText(input(chamber), 'bad');
      await openSensor(tester, minimum);
      await apply(tester);
      expect(find.byKey(const ValueKey(chamber)), findsOneWidget);
      expect(find.byType(RangeSlider), findsNothing);
      expect(
        find.textContaining('Chamber temperature: Enter a finite number.'),
        findsOneWidget,
      );
      expect(writes, isEmpty);
      await finish(tester);
    },
  );

  testWidgets('Apply reopens humidity for an invalid individual bound', (
    tester,
  ) async {
    await mount(tester, openField: minimum);
    await tester.enterText(input(maximum), 'bad');
    await openSensor(tester, chamber);
    await apply(tester);
    expect(find.byType(RangeSlider), findsOneWidget);
    expect(text(tester, maximum), 'bad');
    expect(find.text('Enter a finite number.'), findsOneWidget);
    expect(writes, isEmpty);
    await finish(tester);
  });

  testWidgets('Default stages a value and only Apply writes it to the device', (
    tester,
  ) async {
    await mount(tester);
    final reset = find.byKey(const ValueKey('${chamber}_slider_default'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pump();
    expect(text(tester, chamber), '80');
    expect(state[chamber], 70);
    expect(writes, isEmpty);
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('${chamber}_slider')))
          .onChanged,
      isNotNull,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(text(tester, chamber), '80');
    await apply(tester);
    expect(writes, [
      {chamber: 80},
    ]);
    expect(state[chamber], 80);
    await finish(tester);
  });

  testWidgets(
    'posts only changes and replaces typed representation with confirmation',
    (tester) async {
      await mount(tester);
      await revealInput(tester, chamber);
      await tester.enterText(input(chamber), '85.00');
      await apply(tester);
      expect(writes, [
        {chamber: 85},
      ]);
      await openSensor(tester, chamber);
      expect(text(tester, chamber), '85');

      await finish(tester);
    },
  );

  testWidgets('failed confirmation retains the visible draft', (tester) async {
    client = MockClient(
      (request) async => http.Response(
        jsonEncode(request.method == 'POST' ? {'thresholds': {}} : state),
        200,
      ),
    );
    await mount(tester);
    await revealInput(tester, chamber);
    await tester.enterText(input(chamber), '85');
    await apply(tester);
    expect(text(tester, chamber), '85');
    expect(find.textContaining('Failed to update thresholds'), findsOneWidget);

    await finish(tester);
  });

  testWidgets(
    'catastrophic latch locks manual control despite a chamber fault',
    (tester) async {
      state['active_triggers'] = ['catastrophic_latch', 'temp_sensor_fault'];
      state['chamber_temp_c'] = null;
      state['pump_on'] = true;
      await mount(tester, onAlert: () {}, openField: null);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(
        find.textContaining('Catastrophic Chamber Temperature'),
        findsOneWidget,
      );
      expect(find.text('Sensor fault'), findsOneWidget);
      final pumpCard = find
          .ancestor(of: find.text('Pump Status'), matching: find.byType(Card))
          .first;
      expect(
        find.descendant(of: pumpCard, matching: find.byType(Switch)),
        findsOneWidget,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'environmental alert allows manual control and mute suppresses sound',
    (tester) async {
      var sounds = 0;
      state['active_triggers'] = ['high_pm2_5'];
      await mount(tester, onAlert: () => sounds++, openField: null);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
      expect(sounds, 1);
      await tester.tap(find.byTooltip('Mute app alerts'));
      state['active_triggers'] = ['high_pm2_5', 'high_humidity'];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(sounds, 1);
      await finish(tester);
    },
  );

  testWidgets('offline locks controls and retains edits through reconnect', (
    tester,
  ) async {
    var online = true;
    client = MockClient(
      (request) async => online
          ? http.Response(jsonEncode(state), 200)
          : http.Response('Offline', 503),
    );
    await mount(tester);
    await revealInput(tester, chamber);
    await tester.enterText(input(chamber), '85');
    online = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('ESP32 disconnected'), findsOneWidget);
    expect(tester.widget<TextFormField>(input(chamber)).enabled, isFalse);
    online = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(text(tester, chamber), '85');
    expect(tester.widget<TextFormField>(input(chamber)).enabled, isTrue);
    await finish(tester);
  });

  testWidgets(
    'saving locks inputs and prevents pre-save state overwriting confirmation',
    (tester) async {
      final pending = Completer<http.Response>();
      var gets = 0;
      client = MockClient((request) async {
        if (request.method == 'POST') {
          state[chamber] = 85;
          return http.Response(jsonEncode({'thresholds': state}), 200);
        }
        gets++;
        if (gets == 2) return pending.future;
        return http.Response(jsonEncode(state), 200);
      });
      await mount(tester);
      await revealInput(tester, chamber);
      await tester.enterText(input(chamber), '85');
      await tester.pump(const Duration(seconds: 2));
      await apply(tester);
      pending.complete(http.Response(jsonEncode(snapshot()), 200));
      await tester.pump();
      await openSensor(tester, chamber);
      expect(text(tester, chamber), '85');

      await finish(tester);
    },
  );

  testWidgets(
    'pauses polling during background and resumes without losing draft',
    (tester) async {
      var gets = 0;
      client = MockClient((request) async {
        gets++;
        return http.Response(jsonEncode(state), 200);
      });
      await mount(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 6));
      expect(gets, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(gets, 2);
      await finish(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(gets, 2);
    },
  );

  testWidgets(
    'negative ambient draft survives narrow keyboard scrolling and parent rebuild',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await mount(tester);
      await revealInput(tester, ambient);
      await tester.enterText(input(ambient), '-10.5');
      await tester.ensureVisible(find.text('Apply Thresholds'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(text(tester, ambient), '-10.5');
      await finish(tester);
    },
  );

  testWidgets(
    'a queued manual request rejected with 409 refreshes reported protection',
    (tester) async {
      var posts = 0;
      client = MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          expect(jsonDecode(request.body), {'sprinkler': true});
          state['pump_on'] = true;
          state['sprinkler_on'] = true;
          state['active_triggers'] = ['catastrophic_latch'];
          return http.Response('Automatic safety control is active', 409);
        }
        return http.Response(jsonEncode(state), 200);
      });
      await mount(tester, onAlert: () {}, openField: null);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(posts, 1);
      expect(find.textContaining('Failed to set sprinkler'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      state['pump_on'] = false;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('IDLE'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'pending threshold save locks all controls and suspends polling',
    (tester) async {
      final pending = Completer<http.Response>();
      var gets = 0;
      client = MockClient((request) async {
        if (request.method == 'POST') return pending.future;
        gets++;
        return http.Response(jsonEncode(state), 200);
      });
      await mount(tester);
      await revealInput(tester, chamber);
      await tester.enterText(input(chamber), '85');
      await apply(tester);
      expect(tester.widget<TextFormField>(input(chamber)).enabled, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(gets, 1);
      pending.complete(http.Response('Write failed', 503));
      await tester.pump();
      expect(text(tester, chamber), '85');

      await finish(tester);
    },
  );

  testWidgets(
    'partial confirmation preserves independently supported saved fields',
    (tester) async {
      final pendingPoll = Completer<http.Response>();
      var gets = 0;
      client = MockClient((request) async {
        if (request.method == 'POST') {
          state[chamber] = 85;
          return http.Response(
            '{"thresholds":{"threshold_chamber_temp_c":85}}',
            200,
          );
        }
        if (++gets > 1) return pendingPoll.future;
        return http.Response(jsonEncode(state), 200);
      });
      await mount(tester);
      await revealInput(tester, chamber);
      await tester.enterText(input(chamber), '85');
      await apply(tester);
      await revealInput(tester, minimum);
      expect(tester.widget<TextFormField>(input(minimum)).enabled, isTrue);
      expect(text(tester, minimum), '30');
      await finish(tester);
      pendingPoll.complete(http.Response(jsonEncode(state), 200));
    },
  );

  testWidgets(
    'switch follows canonical reported pump output and locks when unavailable',
    (tester) async {
      state.remove('sprinkler_on');
      state['manual_sprinkler'] = true;
      state['pump_on'] = true;
      await mount(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      state['pump_on'] = 'unknown';
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(find.text('UNAVAILABLE'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'manual command queue retains the latest request and blocks concurrent saves',
    (tester) async {
      final pending = Completer<http.Response>();
      final commands = <bool>[];
      client = MockClient((request) async {
        if (request.method == 'POST') {
          final desired =
              (jsonDecode(request.body) as Map<String, dynamic>)['sprinkler']
                  as bool;
          commands.add(desired);
          state['pump_on'] = desired;
          if (commands.length == 1) return pending.future;
          return http.Response('{"status":"ok"}', 200);
        }
        return http.Response(jsonEncode(state), 200);
      });
      await mount(tester);
      await revealInput(tester, chamber);
      await tester.enterText(input(chamber), '85');
      await tester.pump();
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Apply Thresholds'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(Switch));
      pending.complete(http.Response('{"status":"ok"}', 200));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(commands, [true, false]);
      expect(find.text('IDLE'), findsOneWidget);
      expect(text(tester, chamber), '85');
      await finish(tester);
    },
  );
}
