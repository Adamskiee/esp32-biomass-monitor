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

  group('DashboardScreen Loading and Display', () {
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

    testWidgets('renders dashboard when state is loaded', (tester) async {
      ApiService.client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'chamber_temp': 65.4,
            'mq2_v': 1.25,
            'fan_on': true,
            'sprinkler_on': false,
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
      expect(find.text('Manual Sprinkler'), findsOneWidget);

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      final Switch switchWidget = tester.widget(switchFinder);
      expect(switchWidget.value, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('DashboardScreen Alerting and Mute', () {
    testWidgets('displays alert snackbar and mute button on active triggers',
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
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      // Tap mute button
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();

      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('unmutes when new triggers occur', (tester) async {
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
}
