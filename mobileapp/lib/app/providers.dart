import 'package:biomass_iot_app/app/app.dart';
import 'package:biomass_iot_app/core/device/device_api_client.dart';
import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/alerts/alerts_controller.dart';
import 'package:biomass_iot_app/features/alerts/alerts_store.dart';
import 'package:biomass_iot_app/features/authentication/device_address_store.dart';
import 'package:biomass_iot_app/features/authentication/session_controller.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_history_store.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_controller.dart';
import 'package:biomass_iot_app/features/safety/audit_log_store.dart';
import 'package:biomass_iot_app/features/settings/settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> createApp() async {
  final preferences = await SharedPreferences.getInstance();
  final addresses = DeviceAddressStore(preferences);
  await addresses.migrateLegacyNodes();
  final database = AppDatabase();
  final session = SessionController(
    addresses,
    clientFactory: (ip, authorization) => DeviceApiClient(
      baseUrl: 'http://$ip/api',
      authorizationHeader: authorization,
    ),
  );
  final alerts = AlertsController(AlertsStore(database));
  final telemetry = TelemetryController(
    session,
    SensorHistoryStore(database),
    pollInterval: Duration(seconds: preferences.getInt('pollingInterval') ?? 2),
    onReading: alerts.recordTriggers,
  );
  telemetry.loadHistory();
  alerts.load();
  return MultiProvider(
    providers: [
      Provider.value(value: database),
      Provider.value(value: AuditLogStore(database)),
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: telemetry),
      ChangeNotifierProvider.value(value: alerts),
      ChangeNotifierProvider(create: (_) => SettingsController(preferences)),
    ],
    child: const BiomassApp(),
  );
}
