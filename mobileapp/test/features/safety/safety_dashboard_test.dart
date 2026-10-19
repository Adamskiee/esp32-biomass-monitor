import 'dart:async';
import 'dart:convert';

import 'package:biomass_iot_app/api_service.dart';
import 'package:biomass_iot_app/dashboard.dart';
import 'package:biomass_iot_app/features/safety/widgets/safety_controls_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'compatibility screen hosts the shared panel and retries initial failure',
    (tester) async {
      var online = false;
      final client = MockClient(
        (_) async => online
            ? http.Response(
                jsonEncode({'pump_on': false, 'threshold_chamber_temp_c': 70}),
                200,
              )
            : http.Response('Offline', 503),
      );
      final api = ApiService(
        baseUrl: 'http://device/api',
        authorizationHeader: 'Basic test',
        client: client,
      );
      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(apiService: api)),
      );
      await tester.pump();
      expect(find.textContaining('Failed to connect to ESP32'), findsOneWidget);
      online = true;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.byType(SafetyControlsPanel), findsOneWidget);
      expect(find.text('EcoBurn Safety Dashboard'), findsOneWidget);
      expect(find.text('Live Sensor Data'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(
        find.byKey(const ValueKey('threshold_chamber_temp_c_header')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );

  testWidgets(
    'loading and a disposed pending response leave no polling timer',
    (tester) async {
      final pending = Completer<http.Response>();
      final client = MockClient((_) => pending.future);
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            apiService: ApiService(
              baseUrl: 'http://device/api',
              authorizationHeader: 'Basic test',
              client: client,
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(http.Response('{}', 200));
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      client.close();
    },
  );
}
