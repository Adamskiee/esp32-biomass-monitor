import 'dart:convert';

import 'package:biomass_iot_app/api_service.dart';
import 'package:biomass_iot_app/features/safety/widgets/safety_controls_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MockRingtonePlayer implements FlutterRingtonePlayer {
  int playNotificationCalls = 0;

  @override
  Future<void> playNotification({
    double? volume,
    bool? looping,
    bool asAlarm = false,
  }) async {
    playNotificationCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _baseState() => {
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
  'threshold_chamber_temp_c': 70,
  'threshold_temperature_c': null,
  'threshold_mq2_v': 5,
  'threshold_mq135_v': null,
  'threshold_pm1_0_ug_m3': null,
  'threshold_pm2_5_ug_m3': null,
  'threshold_pm10_ug_m3': null,
  'threshold_humidity_min_percent': 30,
  'threshold_humidity_max_percent': 70,
};

void main() {
  testWidgets(
    'plays notification sound via ringtone player on new trigger when onAlert is omitted',
    (tester) async {
      final state = _baseState();
      state['active_triggers'] = ['high_pm2_5'];
      final player = MockRingtonePlayer();
      final client = MockClient((request) async {
        return http.Response(jsonEncode(state), 200);
      });
      final service = ApiService(
        baseUrl: 'http://device/api',
        authorizationHeader: 'Basic test',
        client: client,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SafetyControlsPanel(
                apiService: service,
                ringtonePlayer: player,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(player.playNotificationCalls, 1);
      client.close();
    },
  );

  testWidgets(
    'suppresses ringtone notification when muted and resumes when alerts clear',
    (tester) async {
      final state = _baseState();
      state['active_triggers'] = ['high_pm2_5'];
      final player = MockRingtonePlayer();
      final client = MockClient((request) async {
        return http.Response(jsonEncode(state), 200);
      });
      final service = ApiService(
        baseUrl: 'http://device/api',
        authorizationHeader: 'Basic test',
        client: client,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SafetyControlsPanel(
                apiService: service,
                ringtonePlayer: player,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(player.playNotificationCalls, 1);

      // Tap mute
      await tester.tap(find.byTooltip('Mute app alerts'));
      await tester.pump();

      // New trigger arrives while muted
      state['active_triggers'] = ['high_pm2_5', 'high_humidity'];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // Sound should still be 1 (suppressed)
      expect(player.playNotificationCalls, 1);

      // Triggers clear -> auto-unmute
      state['active_triggers'] = <String>[];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // New trigger arrives -> sound plays again
      state['active_triggers'] = ['high_pm2_5'];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(player.playNotificationCalls, 2);

      client.close();
    },
  );

  testWidgets(
    'onAlert takes precedence over ringtonePlayer if provided',
    (tester) async {
      final state = _baseState();
      state['active_triggers'] = ['high_pm2_5'];
      final player = MockRingtonePlayer();
      var onAlertCalls = 0;
      final client = MockClient((request) async {
        return http.Response(jsonEncode(state), 200);
      });
      final service = ApiService(
        baseUrl: 'http://device/api',
        authorizationHeader: 'Basic test',
        client: client,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SafetyControlsPanel(
                apiService: service,
                ringtonePlayer: player,
                onAlert: () => onAlertCalls++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(onAlertCalls, 1);
      expect(player.playNotificationCalls, 0);
      client.close();
    },
  );
}
