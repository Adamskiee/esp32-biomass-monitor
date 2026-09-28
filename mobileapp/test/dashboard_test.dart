import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:biomass_iot_app/api_service.dart';
import 'package:biomass_iot_app/dashboard.dart';

void main() {
  setUp(() {
    ApiService.client = http.Client();
  });

  tearDown(() {
    ApiService.client = http.Client();
  });

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      home: child,
    );
  }

  group('DashboardScreen Loading, Error and Display', () {
    testWidgets('displays CircularProgressIndicator when state is empty',
        (tester) async {
      final completer = Completer<http.Response>();
      ApiService.client = MockClient((request) => completer.future);

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Biomass Monitor'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      completer.complete(http.Response('{}', 200));
    });

    testWidgets('displays error view with Retry button on initial fetch failure',
        (tester) async {
      int fetchAttempts = 0;
      ApiService.client = MockClient((request) async {
        fetchAttempts++;
        if (fetchAttempts == 1) {
          return http.Response('Server Error', 500);
        }
        return http.Response(
          jsonEncode({
            'chamber_temp': 55.0,
            'mq2_v': 1.0,
            'fan_on': false,
            'sprinkler_on': false,
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pump();

      expect(find.textContaining('Failed to connect to ESP32'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);

      // Tap Retry
      await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
      await tester.pump();

      expect(find.text('Live Sensor Data'), findsOneWidget);
      expect(find.text('55.0 °C'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('renders full live dashboard and controls when state is loaded',
        (tester) async {
      ApiService.client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'chamber_temp': 65.4,
            'mq2_v': 1.25,
            'fan_on': true,
            'sprinkler_on': false,
            'safe_chamber_limit': 70.0,
            'safe_mq2_limit': 1.8,
            'active_triggers': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Biomass Monitor'), findsOneWidget);
      expect(find.text('Live Sensor Data'), findsOneWidget);
      expect(find.text('65.4 °C'), findsOneWidget);
      expect(find.text('1.25 V'), findsOneWidget);
      expect(find.text('Manual Sprinkler'), findsOneWidget);
      expect(find.text('Safety Thresholds'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('70.0 °C'), 100);
      expect(find.text('70.0 °C'), findsOneWidget);
      expect(find.text('1.80 V'), findsOneWidget);

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      final Switch switchWidget = tester.widget(switchFinder);
      expect(switchWidget.value, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('DashboardScreen Alerting and Mute', () {
    testWidgets('displays red alert snackbar and mute button on active triggers',
        (tester) async {
      ApiService.client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'chamber_temp': 305.0,
            'mq2_v': 1.1,
            'sprinkler_on': true,
            'active_triggers': ['high_chamber_temp'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('DANGER: high_chamber_temp'), findsOneWidget);
      final snackBarFinder = find.byType(SnackBar);
      expect(snackBarFinder, findsOneWidget);
      final SnackBar snackBar = tester.widget(snackBarFinder);
      expect(snackBar.backgroundColor, Colors.red);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      // Tap mute button
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();

      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('does NOT unmute when a trigger is removed', (tester) async {
      List<String> triggers = ['high_chamber_temp', 'high_mq2_gas'];
      ApiService.client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'chamber_temp': 305.0,
            'mq2_v': 2.5,
            'sprinkler_on': true,
            'active_triggers': triggers,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Mute the alert
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      // Trigger removed (only high_chamber_temp remains)
      triggers = ['high_chamber_temp'];

      // Advance periodic timer by 2 seconds
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));

      // Should STAY muted because no NEW trigger was added
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('unmutes only when a truly new trigger occurs', (tester) async {
      List<String> triggers = ['high_chamber_temp'];
      ApiService.client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'chamber_temp': 305.0,
            'mq2_v': 2.5,
            'sprinkler_on': true,
            'active_triggers': triggers,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Mute the alert
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      // New trigger added
      triggers = ['high_chamber_temp', 'high_mq2_gas'];

      // Advance periodic timer by 2 seconds
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));

      // Should automatically unmute
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('dismisses alert when triggers clear', (tester) async {
      List<String> triggers = ['high_chamber_temp'];
      ApiService.client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'chamber_temp': 50.0,
            'mq2_v': 0.5,
            'sprinkler_on': false,
            'active_triggers': triggers,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('DANGER: high_chamber_temp'), findsOneWidget);

      // Clear triggers
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
    testWidgets('queues sprinkler state and sends via ApiService on poll',
        (tester) async {
      bool postedSprinklerState = false;
      bool postReceived = false;

      ApiService.client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'chamber_temp': 50.0,
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

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pump();

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      Switch switchWidget = tester.widget(switchFinder);
      expect(switchWidget.value, isFalse);

      // Toggle switch to ON
      await tester.tap(switchFinder);
      await tester.pump();

      // UI immediately shows queued value true
      switchWidget = tester.widget(switchFinder);
      expect(switchWidget.value, isTrue);

      // Advance timer by 2 seconds so _pollState sends the queued command
      await tester.pump(const Duration(seconds: 2));
      expect(postReceived, isTrue);
      expect(postedSprinklerState, isTrue);

      // Next poll tick fetches state from server
      await tester.pump(const Duration(seconds: 2));
      switchWidget = tester.widget(switchFinder);
      expect(switchWidget.value, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('prevents race condition when toggling switch during in-flight post',
        (tester) async {
      final postCompleter = Completer<http.Response>();
      List<bool> postedCommands = [];

      ApiService.client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'chamber_temp': 50.0,
              'mq2_v': 0.5,
              'sprinkler_on': false,
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

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pump();

      final switchFinder = find.byType(Switch);

      // Toggle switch to true
      await tester.tap(switchFinder);
      await tester.pump();

      // Advance timer by 2s -> enters _pollState, sends true, awaits postCompleter
      await tester.pump(const Duration(seconds: 2));
      expect(postedCommands, [true]);

      // While in-flight, user toggles switch to false!
      await tester.tap(switchFinder);
      await tester.pump();

      // Complete the first in-flight post
      postCompleter.complete(http.Response('{"status":"ok"}', 200));
      await tester.pump();

      // Next poll tick -> should dispatch the newly queued false command!
      await tester.pump(const Duration(seconds: 2));
      expect(postedCommands, [true, false]);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('debounces rapid toggles sending only latest state',
        (tester) async {
      int postCount = 0;
      bool lastPostedState = false;

      ApiService.client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'chamber_temp': 50.0,
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

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pump();

      final switchFinder = find.byType(Switch);

      // Rapidly toggle switch: false -> true -> false -> true
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.tap(switchFinder);
      await tester.pump();

      // Advance timer by 2 seconds
      await tester.pump(const Duration(seconds: 2));

      expect(postCount, 1);
      expect(lastPostedState, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('DashboardScreen Lifecycle and Threshold Controls', () {
    testWidgets('pauses timer on background and resumes on foreground',
        (tester) async {
      int pollCount = 0;
      ApiService.client = MockClient((request) async {
        if (request.method == 'GET') {
          pollCount++;
          return http.Response(
            jsonEncode({
              'chamber_temp': 50.0,
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

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pump();
      expect(pollCount, 1);

      // Advance 2s in foreground -> polls
      await tester.pump(const Duration(seconds: 2));
      expect(pollCount, 2);

      // Simulate app paused (backgrounded)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // Advance 6 seconds while in background -> should NOT poll!
      await tester.pump(const Duration(seconds: 6));
      expect(pollCount, 2);

      // Resume app (foregrounded)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(pollCount, 3); // Immediate poll on resume

      // Advance 2s in foreground -> resumes periodic polling
      await tester.pump(const Duration(seconds: 2));
      expect(pollCount, 4);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('updates safety thresholds via ApiService.setThresholds',
        (tester) async {
      double? savedTemp;
      double? savedMq2;

      ApiService.client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'chamber_temp': 50.0,
              'mq2_v': 0.5,
              'sprinkler_on': false,
              'safe_chamber_limit': 60.0,
              'safe_mq2_limit': 1.5,
              'active_triggers': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path.endsWith('/thresholds')) {
          final data = jsonDecode(request.body);
          savedTemp = (data['safe_chamber_limit'] as num).toDouble();
          savedMq2 = (data['safe_mq2_limit'] as num).toDouble();
          return http.Response('{"status":"ok"}', 200);
        }
        return http.Response('OK', 200);
      });

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pump();

      // Scroll down so Apply Thresholds button is fully visible in viewport
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();

      final applyButton = find.widgetWithText(ElevatedButton, 'Apply Thresholds');
      expect(applyButton, findsOneWidget);
      await tester.tap(applyButton);
      await tester.pump();

      expect(savedTemp, 60.0);
      expect(savedMq2, 1.5);
      expect(find.text('Thresholds updated successfully'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
