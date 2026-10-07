import 'package:biomass_iot_app/api_service.dart';
import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/app/app_shell.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/dashboard.dart';
import 'package:biomass_iot_app/features/authentication/login_screen.dart';
import 'package:biomass_iot_app/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return MaterialApp(
      title: 'Biomass IoT Monitor',
      debugShowCheckedModeBanner: false,
      theme: settings.isDarkMode
          ? AppTheme.getDarkTheme()
          : AppTheme.getLightTheme(),
      home: Consumer<AppStateProvider>(
        builder: (context, state, _) =>
            state.isAuthenticated ? const MainWrapper() : const LoginScreen(),
      ),
      routes: {
        '/dashboard': (context) {
          final state = context.read<AppStateProvider>();
          return DashboardScreen(
            apiService: ApiService(
              baseUrl: 'http://${state.deviceIp}/api',
              authorizationHeader: state.authorizationHeader,
            ),
          );
        },
      },
    );
  }
}
