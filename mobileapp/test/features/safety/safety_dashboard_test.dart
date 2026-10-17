import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:biomass_iot_app/api_service.dart';
import 'package:biomass_iot_app/features/safety/safety_dashboard_screen.dart';

void main() {
  late http.Client client;

  setUp(() {
    client = http.Client();
  });

  tearDown(() {
    client.close();
  });

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(home: child);
  }

  DashboardScreen buildDashboard({VoidCallback? onAlert}) {
    return DashboardScreen(
      apiService: ApiService(
        baseUrl: 'http://192.168.1.51/api',
        authorizationHeader: 'Basic YWRtaW46c2VjcmV0',
        client: client,
      ),
      onAlert: onAlert,
    );
  }

  Finder pumpStatusTile() {
    return find.ancestor(
      of: find.text('Pump Status'),
      matching: find.byType(ListTile),
    );
  }

  group('DashboardScreen Loading, Error and Display', () {
    testWidgets('shows active pump state', (tester) async {
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chamber_temp_c': 55.0,
            'mq2_v': 1.0,
            'pump_on': true,
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();

      final tile = pumpStatusTile();
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text('ACTIVE')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.byType(Switch)),
        findsNothing,
      );
      expect(tester.widget<ListTile>(tile).onTap, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows idle pump state', (tester) async {
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chamber_temp_c': 55.0,
            'mq2_v': 1.0,
            'pump_on': false,
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();

      final tile = pumpStatusTile();
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text('IDLE')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.byType(Switch)),
        findsNothing,
      );
      expect(tester.widget<ListTile>(tile).onTap, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows unavailable when pump state is missing', (tester) async {
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chamber_temp_c': 55.0,
            'mq2_v': 1.0,
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();

      final tile = pumpStatusTile();
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text('UNAVAILABLE')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.byType(Switch)),
        findsNothing,
      );
      expect(tester.widget<ListTile>(tile).onTap, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows unavailable when pump state is malformed', (
      tester,
    ) async {
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chamber_temp_c': 55.0,
            'mq2_v': 1.0,
            'sprinkler_on': true,
            'pump_on': 'on',
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();

      expect(
        find.descendant(
          of: pumpStatusTile(),
          matching: find.text('UNAVAILABLE'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('updates pump status after polling', (tester) async {
      var pumpOn = false;
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chamber_temp_c': 55.0,
            'mq2_v': 1.0,
            'fan_on': false,
            'sprinkler_on': true,
            'pump_on': pumpOn,
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();
      expect(
        find.descendant(of: pumpStatusTile(), matching: find.text('IDLE')),
        findsOneWidget,
      );
      pumpOn = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(
        find.descendant(of: pumpStatusTile(), matching: find.text('ACTIVE')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('displays CircularProgressIndicator when state is empty', (
      tester,
    ) async {
      final completer = Completer<http.Response>();
      client = MockClient((request) => completer.future);

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Biomass Monitor'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      completer.complete(http.Response('{}', 200));
    });

    testWidgets(
      'displays error view with Retry button on initial fetch failure',
      (tester) async {
        int fetchAttempts = 0;
        client = MockClient((request) async {
          fetchAttempts++;
          if (fetchAttempts == 1) {
            return http.Response('Server Error', 500);
          }
          return http.Response(
            jsonEncode({
              'chamber_temp_c': 55.0,
              'mq2_v': 1.0,
              'fan_on': false,
              'sprinkler_on': false,
              'active_triggers': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        await tester.pumpWidget(buildTestableWidget(buildDashboard()));
        await tester.pump();

        expect(
          find.textContaining('Failed to connect to ESP32'),
          findsOneWidget,
        );
        expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
        await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
        await tester.pump();

        expect(find.text('Live Sensor Data'), findsOneWidget);
        expect(find.text('55.0 °C'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'renders full live dashboard and controls when state is loaded',
      (tester) async {
        client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'chamber_temp_c': 65.4,
              'mq2_v': 1.25,
              'pm1_0_ug_m3': 12.0,
              'pm2_5_ug_m3': 34.5,
              'pm10_ug_m3': 56.0,
              'fan_on': true,
              'sprinkler_on': false,
              'threshold_chamber_temp_c': 70.0,
              'threshold_mq2_v': 1.8,
              'threshold_mq135_v': 1.0,
              'threshold_temperature_c': 45.0,
              'threshold_pm1_0_ug_m3': 50.0,
              'threshold_pm2_5_ug_m3': 60.0,
              'threshold_pm10_ug_m3': 70.0,
              'threshold_humidity_min_percent': 30.0,
              'threshold_humidity_max_percent': 70.0,
              'active_triggers': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        await tester.pumpWidget(buildTestableWidget(buildDashboard()));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Biomass Monitor Safety Dashboard'), findsOneWidget);
        expect(find.text('Live Sensor Data'), findsOneWidget);
        expect(find.text('65.4 °C'), findsOneWidget);
        expect(find.text('1.25 V'), findsOneWidget);
        expect(find.text('Particulate Matter'), findsOneWidget);
        expect(find.text('PM1.0: 12 µg/m³'), findsOneWidget);
        expect(find.text('PM2.5: 34.5 µg/m³'), findsOneWidget);
        expect(find.text('PM10: 56 µg/m³'), findsOneWidget);

        await tester.scrollUntilVisible(find.text('Chamber limit (°C)'), 100);
        expect(find.text('Manual Sprinkler'), findsOneWidget);
        expect(find.text('Safety Thresholds'), findsOneWidget);
        expect(find.text('Chamber limit (°C)'), findsOneWidget);

        final switchFinder = find.byType(Switch);
        expect(switchFinder, findsOneWidget);
        final Switch switchWidget = tester.widget(switchFinder);
        expect(switchWidget.value, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('shows unavailable particulate readings when data is absent', (
      tester,
    ) async {
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chamber_temp_c': 55.0,
            'mq2_v': 1.0,
            'pump_on': false,
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();

      expect(find.text('Particulate Matter'), findsOneWidget);
      expect(find.text('PM1.0: --'), findsOneWidget);
      expect(find.text('PM2.5: --'), findsOneWidget);
      expect(find.text('PM10: --'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows particulate readings from legacy API field names', (
      tester,
    ) async {
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chamber_temp_c': 55.0,
            'mq2_v': 1.0,
            'pm1_ug_m3': 10.0,
            'pm25_ug_m3': 20.0,
            'pm10_ug_m3': 30.0,
            'pump_on': false,
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();

      expect(find.text('PM1.0: 10 µg/m³'), findsOneWidget);
      expect(find.text('PM2.5: 20 µg/m³'), findsOneWidget);
      expect(find.text('PM10: 30 µg/m³'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('DashboardScreen Alerting and Mute', () {
    testWidgets(
      'displays red alert snackbar and mute button on active triggers',
      (tester) async {
        client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'chamber_temp_c': 305.0,
              'mq2_v': 1.1,
              'sprinkler_on': true,
              'active_triggers': ['high_chamber_temp'],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        await tester.pumpWidget(buildTestableWidget(buildDashboard()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('DANGER: high_chamber_temp'), findsOneWidget);
        final snackBarFinder = find.byType(SnackBar);
        expect(snackBarFinder, findsOneWidget);
        final SnackBar snackBar = tester.widget(snackBarFinder);
        expect(snackBar.backgroundColor, Colors.red);
        expect(find.byIcon(Icons.volume_up), findsOneWidget);
        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pump();

        expect(find.byIcon(Icons.volume_off), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('does NOT unmute when a trigger is removed', (tester) async {
      List<String> triggers = ['high_chamber_temp', 'high_mq2_gas'];
      client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'chamber_temp_c': 305.0,
            'mq2_v': 2.5,
            'sprinkler_on': true,
            'active_triggers': triggers,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      triggers = ['high_chamber_temp'];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('mute suppresses new trigger sounds until danger clears', (
      tester,
    ) async {
      List<String> triggers = ['high_chamber_temp'];
      var alertSoundCount = 0;
      client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'chamber_temp_c': 305.0,
            'mq2_v': 2.5,
            'sprinkler_on': true,
            'active_triggers': triggers,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(
        buildTestableWidget(buildDashboard(onAlert: () => alertSoundCount++)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(alertSoundCount, 1);

      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      triggers = ['high_chamber_temp', 'high_mq2_gas'];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      expect(alertSoundCount, 1);

      triggers = [];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));

      triggers = ['high_chamber_temp'];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(alertSoundCount, 2);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('dismisses alert when triggers clear', (tester) async {
      List<String> triggers = ['high_chamber_temp'];
      client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'chamber_temp_c': 50.0,
            'mq2_v': 0.5,
            'sprinkler_on': false,
            'active_triggers': triggers,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('DANGER: high_chamber_temp'), findsOneWidget);
      triggers = [];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('DANGER: high_chamber_temp'), findsNothing);
      expect(find.byIcon(Icons.volume_up), findsNothing);
      expect(find.byIcon(Icons.volume_off), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('DashboardScreen Debounced Manual Sprinkler Control', () {
    testWidgets('rejected command clears pending state and resumes polling', (
      tester,
    ) async {
      var fetches = 0;
      var posts = 0;
      client = MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          return http.Response('Automatic safety control is active', 409);
        }
        fetches++;
        return http.Response(
          jsonEncode({
            'chamber_temp_c': 90.0,
            'mq2_v': 0.5,
            'pump_on': true,
            'active_triggers': ['high_chamber_temp'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();
      await tester.scrollUntilVisible(find.byType(Switch), 100);
      await tester.tap(find.byType(Switch));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(posts, 0);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(fetches, 3);
      expect(posts, 0);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('queues sprinkler state and sends via ApiService on poll', (
      tester,
    ) async {
      bool postedSprinklerState = false;
      bool postReceived = false;

      client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'chamber_temp_c': 50.0,
              'mq2_v': 0.5,
              'pump_on': postedSprinklerState,
              'active_triggers': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.method == 'POST') {
          final data = jsonDecode(request.body);
          postedSprinklerState = data['sprinkler'];
          postReceived = true;
          return http.Response('{"status":"ok"}', 200);
        }
        return http.Response('Not Found', 404);
      });

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();

      final switchFinder = find.byType(Switch);
      await tester.scrollUntilVisible(switchFinder, 100);
      expect(switchFinder, findsOneWidget);
      Switch switchWidget = tester.widget(switchFinder);
      expect(switchWidget.value, isFalse);
      await tester.tap(switchFinder);
      await tester.pump();
      switchWidget = tester.widget(switchFinder);
      expect(switchWidget.value, isFalse);
      expect(switchWidget.onChanged, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(postReceived, isTrue);
      expect(postedSprinklerState, isTrue);
      await tester.pump(const Duration(seconds: 2));
      switchWidget = tester.widget(switchFinder);
      expect(switchWidget.value, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'disables switch during an in-flight post until firmware state refreshes',
      (tester) async {
        final postCompleter = Completer<http.Response>();
        List<bool> postedCommands = [];
        var reportedSprinklerState = false;

        client = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'chamber_temp_c': 50.0,
                'mq2_v': 0.5,
                'pump_on': reportedSprinklerState,
                'active_triggers': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          } else if (request.method == 'POST') {
            final data = jsonDecode(request.body);
            postedCommands.add(data['sprinkler']);
            if (postedCommands.length == 1) {
              return postCompleter.future;
            }
            return http.Response('{"status":"ok"}', 200);
          }
          return http.Response('Not Found', 404);
        });

        await tester.pumpWidget(buildTestableWidget(buildDashboard()));
        await tester.pump();

        final switchFinder = find.byType(Switch);
        await tester.scrollUntilVisible(switchFinder, 100);
        await tester.tap(switchFinder);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(postedCommands, [true]);
        expect(tester.widget<Switch>(switchFinder).onChanged, isNull);
        reportedSprinklerState = true;
        postCompleter.complete(http.Response('{"status":"ok"}', 200));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(postedCommands, [true]);
        expect(tester.widget<Switch>(switchFinder).value, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('debounces rapid toggles sending only latest state', (
      tester,
    ) async {
      int postCount = 0;
      bool lastPostedState = false;

      client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'chamber_temp_c': 50.0,
              'mq2_v': 0.5,
              'pump_on': false,
              'active_triggers': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.method == 'POST') {
          postCount++;
          final data = jsonDecode(request.body);
          lastPostedState = data['sprinkler'];
          return http.Response('{"status":"ok"}', 200);
        }
        return http.Response('Not Found', 404);
      });

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();

      final switchFinder = find.byType(Switch);
      await tester.scrollUntilVisible(switchFinder, 100);
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(postCount, 1);
      expect(lastPostedState, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('DashboardScreen Lifecycle and Threshold Controls', () {
    testWidgets('locks threshold inputs while saving', (tester) async {
      final pendingSave = Completer<http.Response>();
      client = MockClient((request) async {
        if (request.method == 'POST') return pendingSave.future;
        return http.Response(
          jsonEncode({
            'chamber_temp_c': 50.0,
            'mq2_v': 0.5,
            'pump_on': false,
            'active_triggers': [],
            'threshold_chamber_temp_c': 60.0,
            'threshold_mq2_v': 1.5,
            'threshold_mq135_v': 1.0,
            'threshold_temperature_c': 45.0,
            'threshold_pm1_0_ug_m3': 50.0,
            'threshold_pm2_5_ug_m3': 60.0,
            'threshold_pm10_ug_m3': 70.0,
            'threshold_humidity_min_percent': 30.0,
            'threshold_humidity_max_percent': 70.0,
          }),
          200,
        );
      });

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Temperature'), 100);
      final chamberInput = find
          .byKey(
            const ValueKey('threshold_chamber_temp_c'),
            skipOffstage: false,
          )
          .last;
      await tester.ensureVisible(chamberInput);
      await tester.enterText(chamberInput, '65');
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pump();
      final apply = find.text('Apply Thresholds');
      await tester.tap(apply);
      await tester.pump();
      expect(tester.widget<TextFormField>(chamberInput).enabled, isFalse);

      pendingSave.complete(
        http.Response('{"thresholds":{"threshold_chamber_temp_c":65}}', 200),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows offline warning after a successful poll goes stale', (
      tester,
    ) async {
      var online = true;
      client = MockClient((request) async {
        if (!online) return http.Response('Unavailable', 503);
        return http.Response(
          jsonEncode({
            'chamber_temp_c': 50.0,
            'mq2_v': 0.5,
            'sprinkler_on': false,
            'active_triggers': [],
          }),
          200,
        );
      });
      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();
      online = false;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('ESP32 disconnected'), findsOneWidget);
      await tester.scrollUntilVisible(find.byType(Switch), 100);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('refreshes untouched thresholds from firmware', (tester) async {
      var chamberLimit = 70.0;
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chamber_temp_c': 50.0,
            'mq2_v': 0.5,
            'sprinkler_on': false,
            'active_triggers': [],
            'threshold_chamber_temp_c': chamberLimit,
            'threshold_mq2_v': 1.5,
          }),
          200,
        ),
      );
      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();
      expect(find.text('Firmware update required'), findsOneWidget);
      chamberLimit = 90.0;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Firmware update required'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('pauses timer on background and resumes on foreground', (
      tester,
    ) async {
      int pollCount = 0;
      client = MockClient((request) async {
        if (request.method == 'GET') {
          pollCount++;
          return http.Response(
            jsonEncode({
              'chamber_temp_c': 50.0,
              'mq2_v': 0.5,
              'sprinkler_on': false,
              'active_triggers': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('OK', 200);
      });

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();
      expect(pollCount, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(pollCount, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(pollCount, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(pollCount, 3);
      await tester.pump(const Duration(seconds: 2));
      expect(pollCount, 4);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'updates edited safety thresholds only after device confirmation',
      (tester) async {
        double? savedTemp;
        double? savedMq2;

        client = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'chamber_temp_c': 50.0,
                'mq2_v': 0.5,
                'sprinkler_on': false,
                'threshold_chamber_temp_c': 60.0,
                'threshold_mq2_v': 1.5,
                'threshold_mq135_v': 1.0,
                'threshold_temperature_c': 45.0,
                'threshold_pm1_0_ug_m3': 50.0,
                'threshold_pm2_5_ug_m3': 60.0,
                'threshold_pm10_ug_m3': 70.0,
                'threshold_humidity_min_percent': 30.0,
                'threshold_humidity_max_percent': 70.0,
                'active_triggers': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          } else if (request.url.path.endsWith('/thresholds')) {
            final data = jsonDecode(request.body);
            savedTemp = (data['threshold_chamber_temp_c'] as num).toDouble();
            savedMq2 = (data['threshold_mq2_v'] as num?)?.toDouble();
            return http.Response(
              '{"thresholds":{"threshold_chamber_temp_c":65,"threshold_mq2_v":1.5}}',
              200,
            );
          }
          return http.Response('OK', 200);
        });

        await tester.pumpWidget(buildTestableWidget(buildDashboard()));
        await tester.pump();
        await tester.scrollUntilVisible(find.text('Temperature'), 100);
        final chamberInput = find
            .byKey(
              const ValueKey('threshold_chamber_temp_c'),
              skipOffstage: false,
            )
            .last;
        await tester.ensureVisible(chamberInput);
        await tester.enterText(chamberInput, '65');
        await tester.pump();

        await tester.drag(find.byType(ListView), const Offset(0, -1200));
        await tester.pump();
        final applyButton = find.widgetWithText(
          ElevatedButton,
          'Apply Thresholds',
        );
        expect(applyButton, findsOneWidget);
        await tester.tap(applyButton);
        await tester.pump();

        expect(savedTemp, 65.0);
        expect(savedMq2, isNull);
        expect(find.text('Thresholds updated successfully'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
