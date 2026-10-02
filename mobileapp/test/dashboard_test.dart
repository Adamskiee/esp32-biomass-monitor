import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:biomass_iot_app/api_service.dart';
import 'package:biomass_iot_app/dashboard.dart';

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

  group('DashboardScreen Loading, Error and Display', () {
    testWidgets('shows active pump state', (tester) async {
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chamber_temp_c': 55.0,
            'mq2_v': 1.0,
            'fan_on': false,
            'sprinkler_on': true,
            'pump_on': true,
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();

      expect(find.text('Pump Status'), findsOneWidget);
      expect(find.text('ACTIVE'), findsWidgets);
      expect(find.byType(Switch), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows idle pump state', (tester) async {
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chamber_temp_c': 55.0,
            'mq2_v': 1.0,
            'fan_on': false,
            'sprinkler_on': true,
            'pump_on': false,
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();

      expect(find.text('Pump Status'), findsOneWidget);
      expect(find.text('IDLE'), findsWidgets);
      expect(find.byType(Switch), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows unavailable when pump state is missing', (tester) async {
      client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chamber_temp_c': 55.0,
            'mq2_v': 1.0,
            'fan_on': false,
            'sprinkler_on': true,
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();

      expect(find.text('Pump Status'), findsOneWidget);
      expect(find.text('UNAVAILABLE'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
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
              'fan_on': true,
              'sprinkler_on': false,
              'threshold_chamber_temp_c': 70.0,
              'threshold_mq2_v': 1.8,
              'active_triggers': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        await tester.pumpWidget(buildTestableWidget(buildDashboard()));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Biomass Monitor'), findsOneWidget);
        expect(find.text('Live Sensor Data'), findsOneWidget);
        expect(find.text('65.4 °C'), findsOneWidget);
        expect(find.text('1.25 V'), findsOneWidget);

        await tester.scrollUntilVisible(find.text('70.0 °C'), 100);
        expect(find.text('Manual Sprinkler'), findsOneWidget);
        expect(find.text('Safety Thresholds'), findsOneWidget);
        expect(find.text('70.0 °C'), findsOneWidget);
        expect(find.text('1.80 V'), findsOneWidget);

        final switchFinder = find.byType(Switch);
        expect(switchFinder, findsOneWidget);
        final Switch switchWidget = tester.widget(switchFinder);
        expect(switchWidget.value, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
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
            'sprinkler_on': true,
            'active_triggers': ['high_chamber_temp'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(posts, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(fetches, 2);
      expect(posts, 1);
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
              'sprinkler_on': postedSprinklerState,
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
                'sprinkler_on': reportedSprinklerState,
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
              'sprinkler_on': false,
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
    testWidgets('locks threshold sliders while saving', (tester) async {
      final pendingSave = Completer<http.Response>();
      client = MockClient((request) async {
        if (request.method == 'POST') return pendingSave.future;
        return http.Response(
          jsonEncode({
            'chamber_temp_c': 50.0,
            'mq2_v': 0.5,
            'sprinkler_on': false,
            'active_triggers': [],
            'threshold_chamber_temp_c': 60.0,
            'threshold_mq2_v': 1.5,
          }),
          200,
        );
      });

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(65.0);
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Apply Thresholds'), 100);
      await tester.tap(find.text('Apply Thresholds'));
      await tester.pump();
      expect(
        tester.widget<Slider>(find.byType(Slider).first).onChanged,
        isNull,
      );

      pendingSave.complete(http.Response('{"status":"ok"}', 200));
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
      await tester.scrollUntilVisible(find.text('70.0 °C'), 100);
      chamberLimit = 90.0;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('90.0 °C'), findsOneWidget);
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

    testWidgets('updates safety thresholds via ApiService.setThresholds', (
      tester,
    ) async {
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
              'active_triggers': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path.endsWith('/thresholds')) {
          final data = jsonDecode(request.body);
          savedTemp = (data['threshold_chamber_temp_c'] as num).toDouble();
          savedMq2 = (data['threshold_mq2_v'] as num).toDouble();
          return http.Response('{"status":"ok"}', 200);
        }
        return http.Response('OK', 200);
      });

      await tester.pumpWidget(buildTestableWidget(buildDashboard()));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(65.0);
      await tester.pump();

      final applyButton = find.widgetWithText(
        ElevatedButton,
        'Apply Thresholds',
      );
      expect(applyButton, findsOneWidget);
      await tester.tap(applyButton);
      await tester.pump();

      expect(savedTemp, 65.0);
      expect(savedMq2, 1.5);
      expect(find.text('Thresholds updated successfully'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
