import 'package:biomass_iot_app/app/app.dart';
import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/features/settings/settings_controller.dart';
import 'package:biomass_iot_app/database_helper.dart';
import 'package:biomass_iot_app/features/experiments/attempt_comparison_service.dart';
import 'package:biomass_iot_app/features/experiments/attempt_controller.dart';
import 'package:biomass_iot_app/features/experiments/attempt_store.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppStateProvider(preferences)),
        ChangeNotifierProxyProvider<AppStateProvider, AttemptController>(
          create: (context) => AttemptController(
            context.read<AppStateProvider>(),
            AttemptStore(DatabaseHelper()),
            const AttemptComparisonService(),
          )..initialize(),
          update: (_, state, controller) => controller!,
        ),
        ChangeNotifierProvider(create: (_) => SettingsController(preferences)),
      ],
      child: const MyApp(),
    ),
  );
}
